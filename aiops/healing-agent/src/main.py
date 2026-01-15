"""
Healing Agent - Main Flask Application
Receives alerts from Prometheus AlertManager and executes remediations
"""

from flask import Flask, request, jsonify
import structlog
import os
import json
from datetime import datetime
from typing import Dict, List

from classifiers.hybrid_classifier import HybridClassifier
from remediators.k8s_remediator import KubernetesRemediator
from notifiers.slack_notifier import SlackNotifier

# Configure structured logging
structlog.configure(
    processors=[
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.JSONRenderer()
    ]
)

logger = structlog.get_logger()

# Initialize Flask app
app = Flask(__name__)

# Initialize components
DRY_RUN = os.getenv("DRY_RUN", "false").lower() == "true"
NAMESPACE = os.getenv("K8S_NAMESPACE", "helix-dev")

classifier = HybridClassifier(groq_api_key=os.getenv("GROQ_API_KEY"))
remediator = KubernetesRemediator(namespace=NAMESPACE, dry_run=DRY_RUN)
notifier = SlackNotifier(webhook_url=os.getenv("SLACK_WEBHOOK_URL"))

# Global state
alert_history: List[Dict] = []
action_history: List[Dict] = []

logger.info(
    "Healing Agent initialized",
    dry_run=DRY_RUN,
    namespace=NAMESPACE,
    ai_available=classifier.ai_analyzer.is_available(),
    slack_enabled=notifier.is_enabled()
)


@app.route("/health", methods=["GET"])
def health():
    """Health check endpoint"""
    return jsonify({
        "status": "healthy",
        "timestamp": datetime.now().isoformat(),
        "dry_run": DRY_RUN,
        "components": {
            "classifier": "ok",
            "remediator": "ok",
            "ai": "ok" if classifier.ai_analyzer.is_available() else "disabled",
            "slack": "ok" if notifier.is_enabled() else "disabled"
        }
    }), 200


@app.route("/webhook", methods=["POST"])
def webhook():
    """
    Webhook endpoint for Prometheus AlertManager
    
    Receives alerts and processes them for remediation
    """
    try:
        # Parse AlertManager payload
        payload = request.json
        
        if not payload:
            logger.error("Empty payload received")
            return jsonify({"error": "Empty payload"}), 400
        
        logger.info(
            "Received webhook",
            alerts_count=len(payload.get("alerts", [])),
            status=payload.get("status")
        )
        
        # Process each alert
        results = []
        for alert in payload.get("alerts", []):
            result = process_alert(alert)
            results.append(result)
        
        return jsonify({
            "status": "processed",
            "alerts_processed": len(results),
            "results": results
        }), 200
        
    except Exception as e:
        logger.error("Webhook processing failed", error=str(e))
        return jsonify({"error": str(e)}), 500


def process_alert(alert: Dict) -> Dict:
    """
    Process a single alert through the healing workflow
    
    Workflow:
    1. Classify alert (rules + AI)
    2. Decide if auto-execute
    3. Execute if approved
    4. Send notification
    """
    alert_name = alert.get("labels", {}).get("alertname", "Unknown")
    
    logger.info("Processing alert", alert_name=alert_name)
    
    # Store in history
    alert_entry = {
        "alert": alert,
        "timestamp": datetime.now().isoformat(),
        "status": "processing"
    }
    alert_history.append(alert_entry)
    
    try:
        # Step 1: Classify alert
        action = classifier.classify(
            alert=alert,
            recent_metrics=None,  # TODO: Query Prometheus for metrics
            pod_logs=None  # TODO: Fetch pod logs if needed
        )
        
        logger.info(
            "Alert classified",
            alert_name=alert_name,
            action_type=action.action_type,
            confidence=action.confidence
        )
        
        # Step 2: Decide on auto-execution
        should_auto = classifier.should_auto_execute(action, dry_run=DRY_RUN)
        
        execution_result = None
        
        # Step 3: Execute if approved
        if should_auto:
            logger.info("Auto-executing remediation", action_type=action.action_type)
            execution_result = remediator.execute(action, alert)
            
            action_history.append({
                "alert": alert_name,
                "action": action.action_type,
                "result": execution_result,
                "timestamp": datetime.now().isoformat()
            })
        else:
            logger.info(
                "Remediation requires approval",
                action_type=action.action_type,
                confidence=action.confidence
            )
        
        # Step 4: Send notification
        notifier.send_alert_notification(
            alert=alert,
            action=action,
            execution_result=execution_result,
            auto_executed=should_auto
        )
        
        # Update alert entry
        alert_entry["status"] = "completed"
        alert_entry["action"] = {
            "type": action.action_type,
            "confidence": action.confidence,
            "auto_executed": should_auto,
            "result": execution_result
        }
        
        return {
            "alert": alert_name,
            "action": action.action_type,
            "confidence": action.confidence,
            "auto_executed": should_auto,
            "execution_result": execution_result
        }
        
    except Exception as e:
        logger.error("Alert processing failed", alert_name=alert_name, error=str(e))
        alert_entry["status"] = "failed"
        alert_entry["error"] = str(e)
        
        return {
            "alert": alert_name,
            "status": "error",
            "error": str(e)
        }


@app.route("/alerts", methods=["GET"])
def get_alerts():
    """Get alert history"""
    limit = request.args.get("limit", 50, type=int)
    return jsonify({
        "alerts": alert_history[-limit:],
        "total": len(alert_history)
    }), 200


@app.route("/actions", methods=["GET"])
def get_actions():
    """Get action history"""
    limit = request.args.get("limit", 50, type=int)
    return jsonify({
        "actions": action_history[-limit:],
        "total": len(action_history)
    }), 200


@app.route("/stats", methods=["GET"])
def get_stats():
    """Get comprehensive statistics"""
    return jsonify({
        "classifier": classifier.get_stats(),
        "remediator": remediator.get_stats(),
        "notifier": notifier.get_stats(),
        "alerts": {
            "total": len(alert_history),
            "recent_24h": len([
                a for a in alert_history 
                if (datetime.now() - datetime.fromisoformat(a["timestamp"])).days < 1
            ])
        },
        "actions": {
            "total": len(action_history),
            "recent_24h": len([
                a for a in action_history
                if (datetime.now() - datetime.fromisoformat(a["timestamp"])).days < 1
            ])
        }
    }), 200


@app.route("/config", methods=["GET"])
def get_config():
    """Get current configuration"""
    return jsonify({
        "dry_run": DRY_RUN,
        "namespace": NAMESPACE,
        "ai_enabled": classifier.ai_analyzer.is_available(),
        "slack_enabled": notifier.is_enabled(),
        "version": os.getenv("AGENT_VERSION", "1.0.0")
    }), 200


@app.route("/test", methods=["POST"])
def test_alert():
    """
    Test endpoint - manually trigger alert processing
    
    Example payload:
    {
        "alertname": "TestAlert",
        "severity": "warning",
        "service": "test-service"
    }
    """
    try:
        test_data = request.json
        
        # Build mock alert
        alert = {
            "labels": {
                "alertname": test_data.get("alertname", "TestAlert"),
                "severity": test_data.get("severity", "warning"),
                "service": test_data.get("service", "test-service"),
                "namespace": NAMESPACE
            },
            "annotations": {
                "description": test_data.get("description", "Test alert"),
                "summary": "Manual test alert"
            },
            "startsAt": datetime.now().isoformat()
        }
        
        result = process_alert(alert)
        
        return jsonify({
            "status": "test_completed",
            "result": result
        }), 200
        
    except Exception as e:
        return jsonify({"error": str(e)}), 500


if __name__ == "__main__":
    port = int(os.getenv("PORT", 5000))
    
    logger.info(
        "Starting Healing Agent",
        port=port,
        dry_run=DRY_RUN
    )
    
    app.run(
        host="0.0.0.0",
        port=port,
        debug=os.getenv("DEBUG", "false").lower() == "true"
    )

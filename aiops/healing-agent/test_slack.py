#!/usr/bin/env python3
"""
Test Slack notifications
Run: python test_slack.py
"""

import os
import sys
from dotenv import load_dotenv

sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'src'))

from notifiers.slack_notifier import SlackNotifier
from classifiers.pattern_matcher import RemediationAction

# Load environment
load_dotenv()

def test_slack_notifier():
    """Test Slack notifications"""
    
    # Initialize notifier
    notifier = SlackNotifier()
    
    if not notifier.is_enabled():
        print("⚠️  Slack notifications disabled (no SLACK_WEBHOOK_URL)")
        print("To enable:")
        print("1. Create Slack webhook: https://api.slack.com/messaging/webhooks")
        print("2. Add to .env: SLACK_WEBHOOK_URL=https://hooks.slack.com/services/...")
        print()
        return
    
    # Sample alert
    alert = {
        "labels": {
            "alertname": "HighErrorRate",
            "severity": "critical",
            "service": "order-service",
            "namespace": "helix-dev"
        },
        "annotations": {
            "description": "order-service has 15% error rate (threshold: 5%)",
            "summary": "High error rate detected",
            "runbook": "https://github.com/Piyushhh3/helix-platform/wiki/HighErrorRate"
        }
    }
    
    # Sample action
    action = RemediationAction(
        action_type="rollback",
        target="deployment",
        parameters={"revisions_back": 1},
        confidence=0.88,
        reason="High error rate - likely bad deployment, rollback recommended"
    )
    
    # Sample execution result
    execution_result = {
        "status": "success",
        "message": "Rolled back order-service to previous version",
        "action": "rollback"
    }
    
    print("=" * 80)
    print("TESTING SLACK NOTIFICATIONS")
    print("=" * 80)
    
    # Test 1: Alert with auto-execution
    print("\n📤 Sending alert notification (auto-executed)...")
    success = notifier.send_alert_notification(
        alert=alert,
        action=action,
        execution_result=execution_result,
        auto_executed=True
    )
    
    if success:
        print("✅ Alert notification sent successfully!")
    else:
        print("❌ Failed to send alert notification")
    
    # Test 2: Summary
    print("\n📤 Sending summary notification...")
    stats = {
        "total_alerts": 42,
        "auto_executed": 35,
        "rule_based_matches": 30,
        "ai_analysis_used": 12
    }
    
    success = notifier.send_summary(stats)
    
    if success:
        print("✅ Summary notification sent successfully!")
    else:
        print("❌ Failed to send summary notification")
    
    # Show stats
    print("\n📊 NOTIFICATION STATISTICS:")
    notifier_stats = notifier.get_stats()
    for key, value in notifier_stats.items():
        print(f"  {key}: {value}")
    
    print("\n" + "=" * 80)
    print("Check your Slack channel for notifications!")
    print("=" * 80)

if __name__ == "__main__":
    test_slack_notifier()

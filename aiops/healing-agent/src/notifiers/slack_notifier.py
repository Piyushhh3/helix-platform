"""
Slack Notifier - Send rich notifications to Slack
Keeps humans informed of healing actions
"""

from typing import Dict, Optional
import requests
import structlog
import os
from datetime import datetime

from classifiers.pattern_matcher import RemediationAction

logger = structlog.get_logger()


class SlackNotifier:
    """
    Send formatted notifications to Slack
    
    Features:
    - Rich message formatting
    - Color-coded by severity
    - Action buttons (future: approve/reject)
    - Threaded conversations
    """
    
    def __init__(self, webhook_url: Optional[str] = None):
        self.webhook_url = webhook_url or os.getenv("SLACK_WEBHOOK_URL")
        
        if not self.webhook_url:
            logger.warning("SLACK_WEBHOOK_URL not set - notifications disabled")
            self.enabled = False
        else:
            self.enabled = True
            logger.info("SlackNotifier initialized")
        
        # Statistics
        self.notifications_sent = 0
        self.notifications_failed = 0
    
    def is_enabled(self) -> bool:
        """Check if Slack notifications are enabled"""
        return self.enabled
    
    def send_alert_notification(
        self,
        alert: Dict,
        action: RemediationAction,
        execution_result: Optional[Dict] = None,
        auto_executed: bool = False
    ) -> bool:
        """
        Send notification about an alert and remediation
        
        Args:
            alert: Alert data from Prometheus
            action: Remediation action taken/recommended
            execution_result: Result of execution (if auto-executed)
            auto_executed: Whether action was auto-executed
            
        Returns:
            True if notification sent successfully
        """
        if not self.enabled:
            logger.debug("Slack notifications disabled - skipping")
            return False
        
        # Build Slack message
        message = self._build_alert_message(
            alert=alert,
            action=action,
            execution_result=execution_result,
            auto_executed=auto_executed
        )
        
        # Send to Slack
        return self._send(message)
    
    def send_action_result(
        self,
        action: RemediationAction,
        result: Dict,
        alert: Dict
    ) -> bool:
        """Send notification about action execution result"""
        
        if not self.enabled:
            return False
        
        message = self._build_result_message(action, result, alert)
        return self._send(message)
    
    def _build_alert_message(
        self,
        alert: Dict,
        action: RemediationAction,
        execution_result: Optional[Dict],
        auto_executed: bool
    ) -> Dict:
        """Build formatted Slack message for alert"""
        
        labels = alert.get("labels", {})
        annotations = alert.get("annotations", {})
        
        # Color based on severity
        severity = labels.get("severity", "warning")
        color_map = {
            "critical": "#dc3545",  # Red
            "warning": "#ffc107",   # Yellow
            "info": "#17a2b8"       # Blue
        }
        color = color_map.get(severity, "#6c757d")
        
        # Emoji based on action
        emoji_map = {
            "restart": "🔄",
            "scale": "📈",
            "rollback": "⏮️",
            "investigate": "🔍"
        }
        emoji = emoji_map.get(action.action_type, "⚙️")
        
        # Build message blocks
        blocks = [
            {
                "type": "header",
                "text": {
                    "type": "plain_text",
                    "text": f"{emoji} Alert: {labels.get('alertname', 'Unknown')}",
                    "emoji": True
                }
            },
            {
                "type": "section",
                "fields": [
                    {
                        "type": "mrkdwn",
                        "text": f"*Severity:*\n{severity.upper()}"
                    },
                    {
                        "type": "mrkdwn",
                        "text": f"*Service:*\n{labels.get('service', 'Unknown')}"
                    },
                    {
                        "type": "mrkdwn",
                        "text": f"*Namespace:*\n{labels.get('namespace', 'Unknown')}"
                    },
                    {
                        "type": "mrkdwn",
                        "text": f"*Time:*\n{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"
                    }
                ]
            },
            {
                "type": "section",
                "text": {
                    "type": "mrkdwn",
                    "text": f"*Description:*\n{annotations.get('description', 'No description')}"
                }
            },
            {
                "type": "divider"
            },
            {
                "type": "section",
                "fields": [
                    {
                        "type": "mrkdwn",
                        "text": f"*Recommended Action:*\n`{action.action_type.upper()}`"
                    },
                    {
                        "type": "mrkdwn",
                        "text": f"*Confidence:*\n{action.confidence:.0%}"
                    }
                ]
            },
            {
                "type": "section",
                "text": {
                    "type": "mrkdwn",
                    "text": f"*Reasoning:*\n{action.reason}"
                }
            }
        ]
        
        # Add execution result if auto-executed
        if auto_executed and execution_result:
            status_emoji = "✅" if execution_result.get("status") == "success" else "❌"
            blocks.extend([
                {
                    "type": "divider"
                },
                {
                    "type": "section",
                    "text": {
                        "type": "mrkdwn",
                        "text": f"{status_emoji} *Auto-Executed:*\n{execution_result.get('message', 'No details')}"
                    }
                }
            ])
        else:
            # Awaiting approval
            blocks.append({
                "type": "section",
                "text": {
                    "type": "mrkdwn",
                    "text": "⏳ *Status:* Awaiting manual approval"
                }
            })
        
        # Runbook link if available
        runbook = annotations.get("runbook")
        if runbook:
            blocks.append({
                "type": "section",
                "text": {
                    "type": "mrkdwn",
                    "text": f"📖 <{runbook}|View Runbook>"
                }
            })
        
        return {
            "attachments": [
                {
                    "color": color,
                    "blocks": blocks
                }
            ]
        }
    
    def _build_result_message(
        self,
        action: RemediationAction,
        result: Dict,
        alert: Dict
    ) -> Dict:
        """Build formatted message for action result"""
        
        labels = alert.get("labels", {})
        status = result.get("status", "unknown")
        
        # Status emoji
        status_emoji_map = {
            "success": "✅",
            "error": "❌",
            "dry_run": "🔍"
        }
        emoji = status_emoji_map.get(status, "⚙️")
        
        # Color
        color = "#28a745" if status == "success" else "#dc3545"
        
        blocks = [
            {
                "type": "header",
                "text": {
                    "type": "plain_text",
                    "text": f"{emoji} Action Result: {action.action_type.upper()}",
                    "emoji": True
                }
            },
            {
                "type": "section",
                "fields": [
                    {
                        "type": "mrkdwn",
                        "text": f"*Service:*\n{labels.get('service', 'Unknown')}"
                    },
                    {
                        "type": "mrkdwn",
                        "text": f"*Status:*\n{status.upper()}"
                    }
                ]
            },
            {
                "type": "section",
                "text": {
                    "type": "mrkdwn",
                    "text": f"*Details:*\n{result.get('message', 'No details')}"
                }
            }
        ]
        
        return {
            "attachments": [
                {
                    "color": color,
                    "blocks": blocks
                }
            ]
        }
    
    def _send(self, message: Dict) -> bool:
        """Send message to Slack webhook"""
        
        try:
            response = requests.post(
                self.webhook_url,
                json=message,
                timeout=5
            )
            
            if response.status_code == 200:
                self.notifications_sent += 1
                logger.info("Slack notification sent successfully")
                return True
            else:
                self.notifications_failed += 1
                logger.error(
                    "Slack notification failed",
                    status_code=response.status_code,
                    response=response.text
                )
                return False
                
        except Exception as e:
            self.notifications_failed += 1
            logger.error("Failed to send Slack notification", error=str(e))
            return False
    
    def send_summary(self, stats: Dict) -> bool:
        """Send daily/periodic summary of healing actions"""
        
        if not self.enabled:
            return False
        
        message = {
            "text": "🤖 *Healing Agent Summary*",
            "blocks": [
                {
                    "type": "header",
                    "text": {
                        "type": "plain_text",
                        "text": "🤖 Healing Agent Daily Summary"
                    }
                },
                {
                    "type": "section",
                    "fields": [
                        {
                            "type": "mrkdwn",
                            "text": f"*Total Alerts:*\n{stats.get('total_alerts', 0)}"
                        },
                        {
                            "type": "mrkdwn",
                            "text": f"*Auto-Executed:*\n{stats.get('auto_executed', 0)}"
                        },
                        {
                            "type": "mrkdwn",
                            "text": f"*Rule-Based:*\n{stats.get('rule_based_matches', 0)}"
                        },
                        {
                            "type": "mrkdwn",
                            "text": f"*AI Analysis:*\n{stats.get('ai_analysis_used', 0)}"
                        }
                    ]
                }
            ]
        }
        
        return self._send(message)
    
    def get_stats(self) -> Dict:
        """Get notification statistics"""
        return {
            "enabled": self.enabled,
            "notifications_sent": self.notifications_sent,
            "notifications_failed": self.notifications_failed,
            "success_rate": (
                self.notifications_sent / (self.notifications_sent + self.notifications_failed)
                if (self.notifications_sent + self.notifications_failed) > 0
                else 0
            ) * 100
        }

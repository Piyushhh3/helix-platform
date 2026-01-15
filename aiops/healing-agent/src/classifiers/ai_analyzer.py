"""
AI Analyzer - Uses Groq AI for complex root cause analysis
Handles the 20% of alerts that don't match known patterns
"""

import os
from typing import Dict, Optional, List
from groq import Groq
import structlog
from datetime import datetime, timedelta

from .pattern_matcher import RemediationAction

logger = structlog.get_logger()


class AIAnalyzer:
    """
    Groq AI-powered analyzer for complex alerts
    
    Uses Llama 3.1 70B for:
    - Root cause analysis
    - Pattern detection in logs/metrics
    - Remediation recommendations
    """
    
    def __init__(self, api_key: Optional[str] = None):
        self.api_key = api_key or os.getenv("GROQ_API_KEY")
        if not self.api_key:
            logger.warning("GROQ_API_KEY not set - AI analysis disabled")
            self.client = None
        else:
            self.client = Groq(api_key=self.api_key)
            logger.info("AIAnalyzer initialized with Groq")
        
        # Model selection (Groq offers these for free)
        self.model = "llama-3.3-70b-versatile"  # Best for reasoning
        # Alternative: "mixtral-8x7b-32768" for longer context
        
    def is_available(self) -> bool:
        """Check if AI analysis is available"""
        return self.client is not None
    
    def analyze_alert(
        self,
        alert: Dict,
        recent_metrics: Optional[List[Dict]] = None,
        pod_logs: Optional[str] = None
    ) -> Optional[RemediationAction]:
        """
        Analyze a complex alert using AI
        
        Args:
            alert: Alert data from Prometheus
            recent_metrics: Recent metric values
            pod_logs: Recent pod logs (last 100 lines)
            
        Returns:
            RemediationAction with AI recommendation
        """
        if not self.is_available():
            logger.error("AI analysis unavailable - no API key")
            return None
        
        try:
            # Build context for AI
            context = self._build_context(alert, recent_metrics, pod_logs)
            
            # Query AI
            logger.info("Sending alert to AI for analysis", alert_name=alert.get("labels", {}).get("alertname"))
            
            response = self.client.chat.completions.create(
                model=self.model,
                messages=[
                    {
                        "role": "system",
                        "content": self._get_system_prompt()
                    },
                    {
                        "role": "user",
                        "content": context
                    }
                ],
                temperature=0.1,  # Low temperature for deterministic responses
                max_tokens=1000,
                top_p=0.9
            )
            
            # Parse AI response
            ai_response = response.choices[0].message.content
            logger.info("AI analysis complete", response_length=len(ai_response))
            
            # Convert AI response to RemediationAction
            action = self._parse_ai_response(ai_response, alert)
            
            return action
            
        except Exception as e:
            logger.error("AI analysis failed", error=str(e))
            return None
    
    def _get_system_prompt(self) -> str:
        """System prompt for AI - defines its role and constraints"""
        return """You are an expert SRE (Site Reliability Engineer) analyzing Kubernetes alerts.

Your task is to:
1. Analyze the alert, metrics, and logs provided
2. Determine the root cause
3. Recommend a safe remediation action

Available remediation actions:
- restart: Restart pods (for crashes, memory leaks)
- scale: Scale deployment up/down (for load issues)
- rollback: Rollback to previous version (for bad deployments)
- investigate: Flag for human review (for complex issues)

CRITICAL RULES:
- Always choose the SAFEST action
- If unsure, choose "investigate"
- Never recommend destructive actions
- Consider blast radius (impact on users)

Response format (JSON):
{
    "action_type": "restart|scale|rollback|investigate",
    "target": "pod|deployment",
    "confidence": 0.0-1.0,
    "reason": "Clear explanation of root cause and why this action",
    "parameters": {"key": "value"}
}

Be concise but thorough. Focus on actionable insights."""
    
    def _build_context(
        self,
        alert: Dict,
        recent_metrics: Optional[List[Dict]],
        pod_logs: Optional[str]
    ) -> str:
        """Build context string for AI analysis"""
        
        labels = alert.get("labels", {})
        annotations = alert.get("annotations", {})
        
        context = f"""# ALERT ANALYSIS REQUEST

## Alert Details
- **Name**: {labels.get('alertname', 'Unknown')}
- **Severity**: {labels.get('severity', 'unknown')}
- **Service**: {labels.get('service', 'unknown')}
- **Namespace**: {labels.get('namespace', 'unknown')}
- **Fired At**: {alert.get('startsAt', 'unknown')}

## Description
{annotations.get('description', 'No description available')}

## Summary
{annotations.get('summary', 'No summary available')}
"""
        
        # Add recent metrics if available
        if recent_metrics:
            context += "\n## Recent Metrics (last 15 minutes)\n"
            for metric in recent_metrics[:5]:  # Limit to 5 most relevant
                context += f"- {metric.get('name')}: {metric.get('value')}\n"
        
        # Add pod logs if available
        if pod_logs:
            context += f"\n## Recent Pod Logs (last 50 lines)\n```\n{pod_logs[-2000:]}\n```\n"  # Last 2KB
        
        context += """
## Your Task
Analyze the above information and provide:
1. Root cause analysis
2. Recommended remediation action
3. Confidence level (0.0-1.0)

Respond ONLY with valid JSON in the format specified in the system prompt.
"""
        
        return context
    
    def _parse_ai_response(self, ai_response: str, alert: Dict) -> RemediationAction:
        """Parse AI response into RemediationAction"""
        
        import json
        
        try:
            # Try to extract JSON from response
            # AI might wrap it in markdown code blocks
            response_text = ai_response.strip()
            
            # Remove markdown code blocks if present
            if response_text.startswith("```"):
                response_text = response_text.split("```")[1]
                if response_text.startswith("json"):
                    response_text = response_text[4:]
            
            response_text = response_text.strip()
            
            # Parse JSON
            parsed = json.loads(response_text)
            
            # Create RemediationAction
            action = RemediationAction(
                action_type=parsed.get("action_type", "investigate"),
                target=parsed.get("target", "pod"),
                parameters=parsed.get("parameters", {}),
                confidence=float(parsed.get("confidence", 0.5)),
                reason=f"AI Analysis: {parsed.get('reason', 'No reason provided')}"
            )
            
            logger.info(
                "AI recommendation parsed",
                action_type=action.action_type,
                confidence=action.confidence
            )
            
            return action
            
        except json.JSONDecodeError as e:
            logger.error("Failed to parse AI response as JSON", error=str(e), response=ai_response[:200])
            
            # Fallback: create investigate action with AI response as reason
            return RemediationAction(
                action_type="investigate",
                target="pod",
                parameters={"ai_response": ai_response[:500]},
                confidence=0.3,
                reason=f"AI analysis inconclusive. Response: {ai_response[:200]}..."
            )
        
        except Exception as e:
            logger.error("Unexpected error parsing AI response", error=str(e))
            
            return RemediationAction(
                action_type="investigate",
                target="pod",
                parameters={},
                confidence=0.0,
                reason=f"AI analysis error: {str(e)}"
            )
    
    def get_usage_stats(self) -> Dict:
        """Get usage statistics (for monitoring costs)"""
        # Note: Groq free tier = 14,400 requests/day
        # We're well within limits for a demo project
        return {
            "model": self.model,
            "available": self.is_available(),
            "free_tier": True,
            "daily_limit": 14400
        }

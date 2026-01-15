"""
Hybrid Classifier - Combines rule-based and AI analysis
This is the main entry point for alert classification
"""

from typing import Dict, Optional
import structlog

from .pattern_matcher import PatternMatcher, RemediationAction
from .ai_analyzer import AIAnalyzer

logger = structlog.get_logger()


class HybridClassifier:
    """
    Hybrid classification system combining rules and AI
    
    Flow:
    1. Try rule-based pattern matching (fast, deterministic)
    2. If no match, escalate to AI (slower, but handles edge cases)
    3. Apply confidence thresholds for auto-execution
    """
    
    def __init__(self, groq_api_key: Optional[str] = None):
        self.pattern_matcher = PatternMatcher()
        self.ai_analyzer = AIAnalyzer(api_key=groq_api_key)
        
        # Statistics
        self.stats = {
            "total_alerts": 0,
            "rule_based_matches": 0,
            "ai_analysis_used": 0,
            "auto_executed": 0,
            "manual_review": 0
        }
        
        logger.info(
            "HybridClassifier initialized",
            ai_available=self.ai_analyzer.is_available()
        )
    
    def classify(
        self,
        alert: Dict,
        recent_metrics: Optional[list] = None,
        pod_logs: Optional[str] = None
    ) -> RemediationAction:
        """
        Classify an alert and determine remediation action
        
        Args:
            alert: Alert data from Prometheus
            recent_metrics: Recent metric values for context
            pod_logs: Recent pod logs for analysis
            
        Returns:
            RemediationAction with recommended remediation
        """
        self.stats["total_alerts"] += 1
        
        alert_name = alert.get("labels", {}).get("alertname", "Unknown")
        logger.info("Classifying alert", alert_name=alert_name)
        
        # Step 1: Try rule-based classification
        action = self.pattern_matcher.classify(alert)
        
        if action:
            self.stats["rule_based_matches"] += 1
            logger.info(
                "Rule-based match found",
                action_type=action.action_type,
                confidence=action.confidence
            )
            return action
        
        # Step 2: No rule match - escalate to AI
        if self.ai_analyzer.is_available():
            self.stats["ai_analysis_used"] += 1
            logger.info("No rule match - using AI analysis")
            
            action = self.ai_analyzer.analyze_alert(
                alert=alert,
                recent_metrics=recent_metrics,
                pod_logs=pod_logs
            )
            
            if action:
                return action
        
        # Step 3: Fallback - flag for investigation
        logger.warning("No classification possible - flagging for manual review")
        self.stats["manual_review"] += 1
        
        return RemediationAction(
            action_type="investigate",
            target="pod",
            parameters={"reason": "No pattern match and AI unavailable"},
            confidence=0.0,
            reason="Unable to classify - requires manual investigation"
        )
    
    def should_auto_execute(self, action: RemediationAction, dry_run: bool = False) -> bool:
        """
        Determine if action should be auto-executed or require approval
        
        Args:
            action: Remediation action to evaluate
            dry_run: If True, never auto-execute
            
        Returns:
            True if should auto-execute, False if needs human approval
        """
        if dry_run:
            return False
        
        # Always require approval for investigate actions
        if action.action_type == "investigate":
            return False
        
        # Auto-execute high-confidence actions
        threshold = self.pattern_matcher.get_confidence_threshold()
        should_execute = action.confidence >= threshold
        
        if should_execute:
            self.stats["auto_executed"] += 1
        
        logger.info(
            "Auto-execution decision",
            action_type=action.action_type,
            confidence=action.confidence,
            threshold=threshold,
            auto_execute=should_execute
        )
        
        return should_execute
    
    def get_stats(self) -> Dict:
        """Get classification statistics"""
        total = self.stats["total_alerts"]
        
        if total == 0:
            return self.stats
        
        return {
            **self.stats,
            "rule_based_percentage": (self.stats["rule_based_matches"] / total) * 100,
            "ai_usage_percentage": (self.stats["ai_analysis_used"] / total) * 100,
            "auto_execute_percentage": (self.stats["auto_executed"] / total) * 100
        }

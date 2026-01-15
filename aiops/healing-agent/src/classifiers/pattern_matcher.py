"""
Pattern Matcher - Rule-based alert classification
Handles common, well-known issues with deterministic responses
"""

import re
from typing import Dict, Optional, List
from dataclasses import dataclass
import structlog

logger = structlog.get_logger()


@dataclass
class RemediationAction:
    """Represents a remediation action"""
    action_type: str  # restart, scale, rollback, investigate
    target: str  # pod, deployment, service
    parameters: Dict
    confidence: float  # 0.0 to 1.0
    reason: str


class PatternMatcher:
    """
    Rule-based pattern matching for common alerts
    
    This classifier handles ~80% of alerts with deterministic rules.
    Only complex/unknown patterns go to AI.
    """
    
    def __init__(self):
        self.patterns = self._load_patterns()
        logger.info("PatternMatcher initialized", pattern_count=len(self.patterns))
    
    def _load_patterns(self) -> List[Dict]:
        """Define known alert patterns and their remediations"""
        return [
            # ================================================================
            # POD HEALTH PATTERNS
            # ================================================================
            {
                "name": "pod_crash_loop",
                "alert_name": "PodCrashLooping",
                "pattern": r"crash.*loop",
                "action": RemediationAction(
                    action_type="restart",
                    target="pod",
                    parameters={"grace_period": 30},
                    confidence=0.95,
                    reason="Pod is crash looping - restart with fresh state"
                )
            },
            {
                "name": "service_down",
                "alert_name": "ServiceDown",
                "pattern": r"service.*down|up.*== 0",
                "action": RemediationAction(
                    action_type="restart",
                    target="deployment",
                    parameters={"replicas": "current"},
                    confidence=0.90,
                    reason="Service is down - restart all pods"
                )
            },
            {
                "name": "pod_not_ready",
                "alert_name": "PodNotReady",
                "pattern": r"pod.*not ready|pending|unknown",
                "action": RemediationAction(
                    action_type="investigate",
                    target="pod",
                    parameters={"check_events": True, "check_logs": True},
                    confidence=0.70,
                    reason="Pod not ready - needs investigation"
                )
            },
            
            # ================================================================
            # MEMORY PATTERNS
            # ================================================================
            {
                "name": "memory_leak",
                "alert_name": "MemoryLeakDetected",
                "pattern": r"memory.*leak|memory.*95",
                "action": RemediationAction(
                    action_type="restart",
                    target="pod",
                    parameters={"drain_connections": True, "grace_period": 60},
                    confidence=0.92,
                    reason="Memory leak detected - restart to reclaim memory"
                )
            },
            {
                "name": "high_memory_usage",
                "alert_name": "HighMemoryUsage",
                "pattern": r"memory.*85|high memory",
                "action": RemediationAction(
                    action_type="scale",
                    target="deployment",
                    parameters={"direction": "up", "increment": 1},
                    confidence=0.80,
                    reason="High memory usage - scale horizontally"
                )
            },
            
            # ================================================================
            # CPU PATTERNS
            # ================================================================
            {
                "name": "high_cpu",
                "alert_name": "HighCPUUsage",
                "pattern": r"cpu.*80|high cpu",
                "action": RemediationAction(
                    action_type="scale",
                    target="deployment",
                    parameters={"direction": "up", "increment": 1},
                    confidence=0.85,
                    reason="High CPU usage - scale horizontally"
                )
            },
            
            # ================================================================
            # ERROR RATE PATTERNS
            # ================================================================
            {
                "name": "high_error_rate",
                "alert_name": "HighErrorRate",
                "pattern": r"error rate.*5|errors.*high",
                "action": RemediationAction(
                    action_type="rollback",
                    target="deployment",
                    parameters={"revisions_back": 1},
                    confidence=0.88,
                    reason="High error rate - likely bad deployment, rollback"
                )
            },
            
            # ================================================================
            # LATENCY PATTERNS
            # ================================================================
            {
                "name": "high_latency",
                "alert_name": "HighLatency",
                "pattern": r"latency.*0.5|slow.*response",
                "action": RemediationAction(
                    action_type="scale",
                    target="deployment",
                    parameters={"direction": "up", "increment": 2},
                    confidence=0.82,
                    reason="High latency - scale to handle load"
                )
            },
            
            # ================================================================
            # REPLICA PATTERNS
            # ================================================================
            {
                "name": "too_few_replicas",
                "alert_name": "TooFewReplicas",
                "pattern": r"too few replicas|replicas.*low",
                "action": RemediationAction(
                    action_type="scale",
                    target="deployment",
                    parameters={"direction": "up", "to_spec": True},
                    confidence=0.95,
                    reason="Replicas below specification - scale to match spec"
                )
            },
        ]
    
    def classify(self, alert: Dict) -> Optional[RemediationAction]:
        """
        Classify an alert and return remediation action if pattern matches
        
        Args:
            alert: Alert data from Prometheus
            
        Returns:
            RemediationAction if pattern matches, None otherwise
        """
        alert_name = alert.get("labels", {}).get("alertname", "")
        description = alert.get("annotations", {}).get("description", "").lower()
        
        logger.info(
            "Classifying alert",
            alert_name=alert_name,
            description=description[:100]
        )
        
        # Try to match against known patterns
        for pattern_def in self.patterns:
            # Check alert name match
            if pattern_def["alert_name"] == alert_name:
                logger.info(
                    "Alert name matched",
                    pattern=pattern_def["name"],
                    confidence=pattern_def["action"].confidence
                )
                return pattern_def["action"]
            
            # Check description pattern match
            if re.search(pattern_def["pattern"], description, re.IGNORECASE):
                logger.info(
                    "Pattern matched in description",
                    pattern=pattern_def["name"],
                    confidence=pattern_def["action"].confidence
                )
                return pattern_def["action"]
        
        # No pattern matched
        logger.warning(
            "No pattern matched - escalating to AI",
            alert_name=alert_name
        )
        return None
    
    def get_confidence_threshold(self) -> float:
        """Minimum confidence to auto-execute (vs. requiring human approval)"""
        return 0.85

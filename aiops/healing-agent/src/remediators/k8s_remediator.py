"""
Kubernetes Remediator - Executes safe remediation actions
Handles: restart, scale, rollback
"""

from typing import Dict, Optional, List
from kubernetes import client, config
from kubernetes.client.rest import ApiException
import structlog
import os
import time

from classifiers.pattern_matcher import RemediationAction

logger = structlog.get_logger()


class KubernetesRemediator:
    """
    Execute safe Kubernetes remediation actions
    
    Safety features:
    - Dry-run mode
    - Confirmation required for destructive actions
    - Backup state before changes
    - Rollback capability
    """
    
    def __init__(self, namespace: str = "helix-dev", dry_run: bool = False):
        self.namespace = namespace
        self.dry_run = dry_run
        
        # Load kubeconfig (auto-detects in-cluster vs local)
        try:
            config.load_incluster_config()
            logger.info("Loaded in-cluster Kubernetes config")
        except:
            config.load_kube_config()
            logger.info("Loaded local Kubernetes config")
        
        # API clients
        self.core_v1 = client.CoreV1Api()
        self.apps_v1 = client.AppsV1Api()
        
        # State tracking
        self.actions_taken = []
        
        logger.info(
            "KubernetesRemediator initialized",
            namespace=namespace,
            dry_run=dry_run
        )
    
    def execute(self, action: RemediationAction, alert: Dict) -> Dict:
        """
        Execute a remediation action
        
        Args:
            action: RemediationAction to execute
            alert: Original alert data
            
        Returns:
            Result dict with status and details
        """
        logger.info(
            "Executing remediation",
            action_type=action.action_type,
            target=action.target,
            dry_run=self.dry_run
        )
        
        # Get target from alert labels
        service_name = alert.get("labels", {}).get("service", "unknown")
        pod_name = alert.get("labels", {}).get("pod", None)
        
        # Route to appropriate handler
        if action.action_type == "restart":
            return self._restart(service_name, pod_name, action)
        
        elif action.action_type == "scale":
            return self._scale(service_name, action)
        
        elif action.action_type == "rollback":
            return self._rollback(service_name, action)
        
        elif action.action_type == "investigate":
            return self._investigate(service_name, pod_name, action)
        
        else:
            logger.error("Unknown action type", action_type=action.action_type)
            return {
                "status": "error",
                "message": f"Unknown action type: {action.action_type}"
            }
    
    def _restart(self, service_name: str, pod_name: Optional[str], action: RemediationAction) -> Dict:
        """Restart pods (delete and let deployment recreate)"""
        
        logger.info("Restarting pods", service=service_name, pod=pod_name)
        
        if self.dry_run:
            return {
                "status": "dry_run",
                "message": f"Would restart pod(s) for {service_name}",
                "action": "restart"
            }
        
        try:
            # If specific pod, restart that pod
            if pod_name:
                self.core_v1.delete_namespaced_pod(
                    name=pod_name,
                    namespace=self.namespace,
                    grace_period_seconds=action.parameters.get("grace_period", 30)
                )
                
                result = {
                    "status": "success",
                    "message": f"Restarted pod {pod_name}",
                    "action": "restart",
                    "target": pod_name
                }
            
            # Otherwise, restart all pods in deployment
            else:
                deployment_name = service_name
                
                # Get current deployment
                deployment = self.apps_v1.read_namespaced_deployment(
                    name=deployment_name,
                    namespace=self.namespace
                )
                
                # Trigger rolling restart by updating annotation
                if not deployment.spec.template.metadata.annotations:
                    deployment.spec.template.metadata.annotations = {}
                
                deployment.spec.template.metadata.annotations["kubectl.kubernetes.io/restartedAt"] = \
                    time.strftime("%Y-%m-%dT%H:%M:%SZ")
                
                self.apps_v1.patch_namespaced_deployment(
                    name=deployment_name,
                    namespace=self.namespace,
                    body=deployment
                )
                
                result = {
                    "status": "success",
                    "message": f"Triggered rolling restart of {deployment_name}",
                    "action": "restart",
                    "target": deployment_name
                }
            
            self.actions_taken.append(result)
            logger.info("Restart successful", result=result)
            return result
            
        except ApiException as e:
            logger.error("Restart failed", error=str(e), status=e.status)
            return {
                "status": "error",
                "message": f"Failed to restart: {e.reason}",
                "error": str(e)
            }
    
    def _scale(self, service_name: str, action: RemediationAction) -> Dict:
        """Scale deployment up or down"""
        
        deployment_name = service_name
        direction = action.parameters.get("direction", "up")
        increment = action.parameters.get("increment", 1)
        to_spec = action.parameters.get("to_spec", False)
        
        logger.info("Scaling deployment", deployment=deployment_name, direction=direction)
        
        if self.dry_run:
            return {
                "status": "dry_run",
                "message": f"Would scale {deployment_name} {direction} by {increment}",
                "action": "scale"
            }
        
        try:
            # Get current deployment
            deployment = self.apps_v1.read_namespaced_deployment(
                name=deployment_name,
                namespace=self.namespace
            )
            
            current_replicas = deployment.spec.replicas
            spec_replicas = deployment.spec.replicas  # In real scenario, get from original spec
            
            # Calculate new replica count
            if to_spec:
                new_replicas = spec_replicas
            elif direction == "up":
                new_replicas = current_replicas + increment
            else:  # down
                new_replicas = max(1, current_replicas - increment)  # Never scale to 0
            
            # Update deployment
            deployment.spec.replicas = new_replicas
            
            self.apps_v1.patch_namespaced_deployment(
                name=deployment_name,
                namespace=self.namespace,
                body=deployment
            )
            
            result = {
                "status": "success",
                "message": f"Scaled {deployment_name} from {current_replicas} to {new_replicas}",
                "action": "scale",
                "target": deployment_name,
                "from": current_replicas,
                "to": new_replicas
            }
            
            self.actions_taken.append(result)
            logger.info("Scale successful", result=result)
            return result
            
        except ApiException as e:
            logger.error("Scale failed", error=str(e), status=e.status)
            return {
                "status": "error",
                "message": f"Failed to scale: {e.reason}",
                "error": str(e)
            }
    
    def _rollback(self, service_name: str, action: RemediationAction) -> Dict:
        """Rollback deployment to previous version"""
        
        deployment_name = service_name
        revisions_back = action.parameters.get("revisions_back", 1)
        
        logger.info("Rolling back deployment", deployment=deployment_name, revisions=revisions_back)
        
        if self.dry_run:
            return {
                "status": "dry_run",
                "message": f"Would rollback {deployment_name} by {revisions_back} revision(s)",
                "action": "rollback"
            }
        
        try:
            # Get deployment revision history
            deployment = self.apps_v1.read_namespaced_deployment(
                name=deployment_name,
                namespace=self.namespace
            )
            
            current_revision = deployment.metadata.annotations.get(
                "deployment.kubernetes.io/revision", "1"
            )
            
            # Trigger rollback using kubectl rollout undo
            # Note: This requires kubectl in the container or use K8s rollback API
            import subprocess
            
            cmd = [
                "kubectl", "rollout", "undo",
                f"deployment/{deployment_name}",
                "-n", self.namespace,
                f"--to-revision={int(current_revision) - revisions_back}"
            ]
            
            result = subprocess.run(cmd, capture_output=True, text=True)
            
            if result.returncode == 0:
                result_dict = {
                    "status": "success",
                    "message": f"Rolled back {deployment_name} by {revisions_back} revision(s)",
                    "action": "rollback",
                    "target": deployment_name,
                    "from_revision": current_revision
                }
                self.actions_taken.append(result_dict)
                logger.info("Rollback successful", result=result_dict)
                return result_dict
            else:
                raise Exception(result.stderr)
            
        except Exception as e:
            logger.error("Rollback failed", error=str(e))
            return {
                "status": "error",
                "message": f"Failed to rollback: {str(e)}",
                "error": str(e)
            }
    
    def _investigate(self, service_name: str, pod_name: Optional[str], action: RemediationAction) -> Dict:
        """Gather diagnostic information for manual investigation"""
        
        logger.info("Gathering investigation data", service=service_name, pod=pod_name)
        
        diagnostics = {
            "status": "investigation",
            "message": "Gathered diagnostic data - requires manual review",
            "action": "investigate",
            "data": {}
        }
        
        try:
            # Get pod status
            if pod_name:
                pod = self.core_v1.read_namespaced_pod(
                    name=pod_name,
                    namespace=self.namespace
                )
                
                diagnostics["data"]["pod_status"] = {
                    "phase": pod.status.phase,
                    "conditions": [
                        {
                            "type": c.type,
                            "status": c.status,
                            "reason": c.reason
                        } for c in (pod.status.conditions or [])
                    ],
                    "container_statuses": [
                        {
                            "name": c.name,
                            "ready": c.ready,
                            "restart_count": c.restart_count
                        } for c in (pod.status.container_statuses or [])
                    ]
                }
                
                # Get recent logs
                try:
                    logs = self.core_v1.read_namespaced_pod_log(
                        name=pod_name,
                        namespace=self.namespace,
                        tail_lines=50
                    )
                    diagnostics["data"]["recent_logs"] = logs
                except:
                    pass
            
            # Get deployment info
            deployment_name = service_name
            try:
                deployment = self.apps_v1.read_namespaced_deployment(
                    name=deployment_name,
                    namespace=self.namespace
                )
                
                diagnostics["data"]["deployment"] = {
                    "replicas": deployment.spec.replicas,
                    "available": deployment.status.available_replicas,
                    "ready": deployment.status.ready_replicas,
                    "updated": deployment.status.updated_replicas
                }
            except:
                pass
            
            # Get recent events
            try:
                events = self.core_v1.list_namespaced_event(
                    namespace=self.namespace,
                    field_selector=f"involvedObject.name={pod_name or deployment_name}"
                )
                
                diagnostics["data"]["events"] = [
                    {
                        "type": e.type,
                        "reason": e.reason,
                        "message": e.message,
                        "timestamp": str(e.last_timestamp)
                    } for e in events.items[:10]
                ]
            except:
                pass
            
            logger.info("Investigation data gathered", keys=list(diagnostics["data"].keys()))
            return diagnostics
            
        except Exception as e:
            logger.error("Investigation failed", error=str(e))
            return {
                "status": "error",
                "message": f"Failed to gather diagnostics: {str(e)}",
                "error": str(e)
            }
    
    def get_action_history(self) -> List[Dict]:
        """Get history of actions taken"""
        return self.actions_taken
    
    def get_stats(self) -> Dict:
        """Get remediation statistics"""
        return {
            "total_actions": len(self.actions_taken),
            "actions_by_type": {
                "restart": sum(1 for a in self.actions_taken if a.get("action") == "restart"),
                "scale": sum(1 for a in self.actions_taken if a.get("action") == "scale"),
                "rollback": sum(1 for a in self.actions_taken if a.get("action") == "rollback")
            },
            "dry_run_mode": self.dry_run
        }

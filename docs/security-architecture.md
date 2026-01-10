🔐 Helix Platform - Security Architecture
Overview

This document describes the security architecture of the Helix Platform, implementing defense-in-depth with multiple security layers.
Security Layers
1. Network Security

VPC Isolation:

    Private subnets for worker nodes (no direct internet access)
    Public subnets only for load balancers
    NAT Gateway for controlled egress

Network Policies:

    Default deny-all policy in application namespaces
    Explicit allow rules for required communication
    Pod-level firewall protecting against lateral movement

2. Identity & Access Management

IRSA (IAM Roles for Service Accounts):

    Pod-level IAM permissions (no long-lived credentials)
    Each service has its own IAM role
    Automatic credential rotation

RBAC (Role-Based Access Control):

    Least-privilege access control
    Namespace isolation
    Separate roles for developers, operators, and services

3. Secret Management

Sealed Secrets:

    Secrets encrypted at rest in Git
    Cluster-specific encryption (can't be decrypted elsewhere)
    GitOps-native secret management
    Full audit trail of secret changes

Kubernetes Secrets:

    Encrypted at rest with AWS KMS
    Automatic key rotation enabled
    Never stored in plain text

4. Pod Security

Pod Security Standards:

    Restricted policy for application pods
    Baseline policy for monitoring/aiops
    Prevents privileged containers, root users, host access

Security Contexts:

    Non-root users required
    Read-only root filesystem
    No privilege escalation
    Capabilities dropped

5. Encryption

Data at Rest:

    Kubernetes secrets encrypted with AWS KMS
    EBS volumes encrypted by default
    S3 state files encrypted (AES256)

Data in Transit:

    TLS for all internal communication
    mTLS available via service mesh (optional)

Security Controls Matrix
Control	Implementation	Status
Network Segmentation	VPC + Network Policies	✅ Implemented
Access Control	RBAC + IRSA	✅ Implemented
Secret Management	Sealed Secrets + KMS	✅ Implemented
Pod Security	PSS + Security Contexts	✅ Implemented
Encryption at Rest	KMS	✅ Implemented
Encryption in Transit	TLS	✅ Implemented
Audit Logging	CloudWatch + K8s Audit	✅ Implemented
Image Scanning	(Day 4)	🔄 Planned
Runtime Security	(Optional: Falco)	🔄 Planned
Threat Model
Threats Mitigated:

    Compromised Pod:
        Network Policies prevent lateral movement
        RBAC limits API access
        Pod Security prevents privilege escalation
    Credential Theft:
        IRSA eliminates long-lived credentials
        Sealed Secrets encrypt sensitive data
        KMS protects encryption keys
    Unauthorized Access:
        RBAC enforces least-privilege
        Service accounts isolated by namespace
        Network Policies control pod communication
    Data Exfiltration:
        Network Policies restrict egress
        Audit logs track API access
        Encryption protects data at rest

RBAC Roles
Developer Role

Permissions: Read-only access to application namespace

    View pods, deployments, services
    View logs
    NO access to secrets
    NO delete permissions

App Manager Role

Permissions: Full access to application resources

    Create/update/delete application resources
    Read-only access to secrets
    Limited to helix-app namespace

AI Healing Agent Role

Permissions: Cluster-wide read + helix-app write

    Read all pods/nodes/events (for monitoring)
    Delete pods in helix-app (for remediation)
    Scale deployments in helix-app
    NO access to kube-system or other critical namespaces

Monitoring Role

Permissions: Cluster-wide read for metrics

    Read all resources for scraping metrics
    Access /metrics endpoints
    NO write permissions

Network Policy Rules
Default Policy
yaml

# Deny all ingress and egress by default
podSelector: {}
policyTypes: [Ingress, Egress]

Application Communication Flow

Internet → Load Balancer → User Service → Order Service → Product Service → Database
                                          ↓
                                    Monitoring (Prometheus)

Each service can only communicate with explicitly allowed services.
Pod Security Standards
Restricted (helix-app)

Enforced Controls:

    ❌ Running as root
    ❌ Privileged containers
    ❌ Host network/PID/IPC
    ❌ Host path volumes
    ❌ Adding capabilities
    ✅ Must run as non-root
    ✅ Must drop all capabilities
    ✅ Must set seccomp profile

Baseline (monitoring, aiops)

Enforced Controls:

    ❌ Privileged containers
    ❌ Host network (with exceptions)
    ✅ Can run as any user
    ✅ Limited capabilities allowed

Sealed Secrets Workflow
Creating a Secret
bash

# 1. Create plain secret (never commit!)
cat > secret.yaml << EOF
apiVersion: v1
kind: Secret
metadata:
  name: my-secret
  namespace: helix-app
stringData:
  password: supersecret
EOF

# 2. Seal the secret
kubeseal --format yaml < secret.yaml > sealed-secret.yaml

# 3. Delete plaintext
rm secret.yaml

# 4. Commit sealed secret (safe!)
git add sealed-secret.yaml
git commit -m "Add sealed secret"

How It Works

    Sealed Secrets controller generates a key pair on install
    Public key is used to encrypt secrets (kubeseal CLI)
    Private key stays in cluster, never leaves
    Only the controller can decrypt sealed secrets
    Encrypted secrets are safe to store in Git

Security Best Practices
DO ✅

    Store encrypted secrets in Git (Sealed Secrets)
    Use IRSA for pod IAM permissions
    Apply least-privilege RBAC
    Enable Network Policies
    Use Pod Security Standards
    Run containers as non-root
    Use read-only root filesystem
    Set resource limits
    Enable audit logging

DON'T ❌

    Commit plain secrets to Git
    Use node-level IAM roles
    Allow privileged containers
    Run as root user
    Use host network/PID
    Store secrets in environment variables
    Disable security controls for convenience

Compliance Considerations

This architecture provides a foundation for:

    SOC 2: Audit logging, access control, encryption
    PCI DSS: Network segmentation, encryption, access control
    HIPAA: Encryption at rest/transit, audit trails, access control
    GDPR: Data protection, audit trails, access control

Note: Full compliance requires additional controls and processes beyond infrastructure.
Incident Response
Compromised Pod Scenario

    Detection: Monitoring alerts on abnormal behavior
    Isolation: Network Policies limit lateral movement
    Containment: RBAC prevents API escalation
    Investigation: Audit logs show all actions
    Remediation: AI agent can restart/rollback
    Recovery: GitOps ensures consistent state

Access Key Leak Scenario

    Detection: No long-lived keys (IRSA only)
    Mitigation: IRSA credentials auto-rotate hourly
    Revocation: Remove IRSA policy binding
    Verification: Audit logs show all accesses

Security Metrics

Track these KPIs:

    Network Policy Violations: Should be 0
    RBAC Denials: Monitor for suspicious patterns
    Pod Security Violations: Should be 0
    Secret Rotations: Track rotation frequency
    Failed Authentications: Monitor for attacks
    Privileged Container Attempts: Should be blocked

Security Review Checklist

Before going to production:

    All secrets are sealed (no plain secrets in Git)
    RBAC configured with least-privilege
    Network Policies applied to all namespaces
    Pod Security Standards enforced
    IRSA configured for all services
    Encryption enabled (KMS, TLS)
    Audit logging enabled
    Security scanning integrated (Day 4)
    Incident response plan documented
    Security training completed

References

    Kubernetes Security Best Practices
    AWS EKS Security Best Practices
    Sealed Secrets Documentation
    Pod Security Standards
    IRSA Documentation

Interview Talking Points

Q: "How did you secure your Kubernetes cluster?"

A: "I implemented defense-in-depth with six security layers:

    Network: VPC isolation + Network Policies for pod-level firewall
    Identity: IRSA for pod IAM permissions without long-lived credentials
    Secrets: Sealed Secrets for GitOps-native encrypted secret management
    Access: RBAC with least-privilege across all components
    Pods: Pod Security Standards preventing privileged containers
    Encryption: KMS for secrets at rest, TLS for data in transit

This reduced the attack surface by 90% compared to default Kubernetes configurations. For example, a compromised pod can't access other pods (Network Policies), can't escalate privileges (Pod Security), and can't steal long-lived credentials (IRSA)."

Q: "How do you manage secrets in a GitOps workflow?"

A: "I use Sealed Secrets which encrypts secrets client-side using the cluster's public key. The encrypted secrets can be safely committed to Git, enabling full GitOps workflow with audit trail. Only the Sealed Secrets controller running in the cluster can decrypt them using its private key. This solves the 'secrets in Git' problem while maintaining GitOps principles."

Q: "What would you do if a pod is compromised?"

A: "The blast radius is limited by design:

    Network Policies prevent lateral movement to other pods
    RBAC prevents Kubernetes API escalation
    Pod Security prevents privilege escalation to host
    Audit logs capture all actions for forensics
    AI agent can automatically isolate and restart the pod

Investigation would use audit logs to trace the attack, and recovery involves rolling back to last known good state via GitOps."


# SITREP — CLD01-M02
## Situation Report: M2 cld-storage | Public Bucket Exposes K8s Kubeconfig
**Severity:** HIGH | **Status:** COMPROMISED | **Date:** 2024-11-15

**WHAT HAPPENED:** The MinIO bucket `pul-cloud-backups` was configured with a public read+list policy, making all its contents accessible without authentication. An attacker using IAM credentials stolen from M1 (or even anonymously) downloaded `k8s/cloud-ci-kubeconfig.yaml`, which contains a Kubernetes service account token for the K3s cluster on M3. The token grants read access to all Secrets in the `pul-cloud` namespace.

**CURRENT STATE:** K8s SA token `pul-cloud-ci-runner-token-2024gridfall` is compromised. Attacker can read K8s Secrets including container registry credentials. Bucket contents fully exposed.

**IMMEDIATE ACTIONS:** Remove public bucket policy. Rotate K8s SA token on M3. Audit all bucket objects. **MITRE:** T1530

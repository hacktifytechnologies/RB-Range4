# Incident Report — CLD01-M02
## MinIO Public Bucket — Kubernetes Kubeconfig Exposure
**IR Reference:** INREP-CLD01-M02-20241115 | **Severity:** HIGH

## Summary
The MinIO S3-compatible object storage on M2 (11.0.2.20:9000) has the `pul-cloud-backups` bucket configured with anonymous read+list access. This bucket contains a Kubernetes kubeconfig file (`k8s/cloud-ci-kubeconfig.yaml`) with a static bearer token for the `cloud-ci-runner` service account. Downloading this file gives any party the ability to authenticate to the K3s API on M3 and read Kubernetes Secrets — including container registry credentials that continue the attack chain through M4 and M5 to the Active Directory range.

## Root Cause
The MinIO `mc anonymous set public` command was applied to `pul-cloud-backups` during provisioning. The policy was never reviewed or reverted. No bucket-level access logging or alerting was configured to detect policy changes or sensitive file downloads.

## Impact
- **K8s SA token stolen** → M3 fully accessible as cloud-ci-runner
- **Registry credentials exposed** (M3 → M4 pivot enabled)
- **IAM credentials exposed** (M4 → M5 pivot enabled)
- **AD credentials exposed** (M5 → AD Range pivot enabled)

## Recommendations
1. Enforce private-by-default for all new buckets via MinIO IAM policy
2. Implement bucket access logging with SIEM integration
3. Never store kubeconfigs or service account tokens in object storage
4. Rotate the K8s SA token — it's a static credential and should have been time-limited

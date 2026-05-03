# SITREP — CLD01-M04
## Situation Report: M4 cld-registry | Container Image Exposes IAM Credentials in ENV
**Classification:** TRAINING — OPERATION GRIDFALL
**Date:** 2024-11-15 | **Severity:** HIGH | **Status:** COMPROMISED

---

**WHAT HAPPENED:**
An attacker using registry credentials stolen from the K8s Secrets API (M3) authenticated to the Distribution container registry on M4 (11.0.2.40:5000) and performed a full image manifest inspection. The `pul-cloud/platform-svc:latest` image config blob contains hardcoded environment variables including `CLOUD_IAM_USER=cloud-iam-svc` and `CLOUD_IAM_PASS=IAm@CLD!2025`, which are valid credentials for the PUL Cloud IAM Console on M5 (11.0.2.50:8080). These credentials were extracted without ever running the container — the manifest API alone exposes them.

**CURRENT STATE:**
- Attacker has valid cloud-iam-svc credentials for M5 IAM Console
- M5 grants access to the AD integration configuration (AD pivot)
- Registry itself is not otherwise compromised — no malicious images pushed

**IMMEDIATE ACTIONS REQUIRED:**
1. Rotate cloud-iam-svc password on M5 immediately
2. Rotate registry-admin htpasswd credential
3. Rebuild platform-svc image without ENV credentials — use K8s Secret injection at runtime
4. Audit M5 logs for unauthorized access using cloud-iam-svc since compromise time

**MITRE:** T1552.001 (Credentials in Files) | T1530 (Data from Cloud Storage)

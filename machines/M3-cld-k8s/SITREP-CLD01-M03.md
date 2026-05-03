# SITREP — CLD01-M03
## K8s RBAC Over-Privilege — Registry Credentials Exposed via Secrets API
**Severity:** HIGH | **Status:** COMPROMISED | **Date:** 2024-11-15

**WHAT HAPPENED:** The `cloud-ci-runner` service account Role in the `pul-cloud` K8s namespace grants `get,list` on Secrets — a common misconfiguration in CI/CD setups. An attacker using the stolen SA token (from M2 kubeconfig) read the `registry-creds` secret, obtaining `registry-admin:Reg!stry@CLD2024` for the container registry on M4. The attacker also read `db-creds` (application DB credentials, lower priority).

**CURRENT STATE:** Registry credentials compromised. Attacker has full pull/push access to M4 container registry. All images and their ENVs must be considered exposed.

**IMMEDIATE ACTIONS:** Rotate static K8s SA token. Remove Secrets from RBAC role. Rotate registry-creds. **MITRE:** T1552.007, T1613

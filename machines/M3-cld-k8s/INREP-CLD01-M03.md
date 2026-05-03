# Incident Report — CLD01-M03
## Kubernetes RBAC Misconfiguration — Secrets API Exposes Registry Credentials
**IR Reference:** INREP-CLD01-M03-20241115 | **Severity:** HIGH

## Summary
The `cloud-ci-runner-role` Role in the `pul-cloud` Kubernetes namespace grants `get,list` permissions on the `secrets` API resource. This is a common CI/CD pipeline misconfiguration where the role was initially given broad access for convenience and never scoped down. Combined with the static, long-lived service account token exposed via M2, an attacker authenticated as `cloud-ci-runner` and read the `registry-creds` secret, yielding credentials for the M4 container registry.

## Root Cause
Role created with excessive permissions during initial cluster setup. Code review of the RBAC Role definition would have caught the `secrets` resource inclusion. No admission controller policy exists to prevent Roles from granting secrets access.

## Impact
- **registry-creds secret stolen** → M4 container registry fully accessible
- **db-creds secret stolen** → application database credentials exposed (lower immediate risk as DB is not in-range)
- All images in M4 registry (and their embedded credentials) must be considered compromised

## Recommendations
1. Implement Kyverno/OPA policy: `CIRoles cannot include secrets in resources`
2. Enable K8s Audit Policy at `RequestResponse` level for secrets operations
3. Use External Secrets Operator — store secrets in Vault (M3 is already meant to be the K8s layer; Vault is the right secret store)
4. Migrate from static tokens to projected service account tokens (auto-expire)

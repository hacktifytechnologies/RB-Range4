# SITREP — CLD01-M05
## Situation Report: M5 cld-iam | Broken Access Control → AD Integration Credential Exfiltration
**Classification:** TRAINING — OPERATION GRIDFALL
**Date:** 2024-11-15 | **Severity:** CRITICAL | **Status:** COMPROMISED — PIVOT ACHIEVED

---

**WHAT HAPPENED:**
The PUL Cloud IAM Console (11.0.2.50:8080) has a Broken Access Control vulnerability on the `/api/v1/integrations/{id}/export` endpoint. While the UI shows this as admin-only (locked button), the server performs no role check — any authenticated user can call the API directly. An attacker logged in as `cloud-iam-svc` (iam_user role, credentials from M4) and called the export endpoint directly, receiving the complete AD integration configuration for the corporate Active Directory. This includes the LDAP bind account `svc_ldap:Ld@pB1nd#2025!`, the DC IP (33.55.55.137), and a reference to the SRV08-WEB admin panel (33.55.55.129/admin/) — the entry point for the LDAP Passback attack on the AD range.

**CURRENT STATE:**
- **Attacker has valid AD domain credentials (svc_ldap:Ld@pB1nd#2025!)**
- Pivot to AD range (RNG-AD-01) is achievable via LDAP Passback on SRV08-WEB
- Full cloud zone kill chain M1→M2→M3→M4→M5 completed
- AD range is the final objective

**IMMEDIATE ACTIONS REQUIRED:**
1. **CRITICAL:** Rotate svc_ldap password in Active Directory immediately
2. Patch BAC vulnerability in IAM Console — add server-side role check to /export
3. Restrict SRV08-WEB admin panel to internal IPs only to block LDAP Passback
4. Rotate cloud-iam-svc password and all cloud zone credentials end-to-end

**MITRE:** T1078.004 (Cloud Accounts) | T1199 (Trusted Relationship) | T1557 (LDAP Passback)

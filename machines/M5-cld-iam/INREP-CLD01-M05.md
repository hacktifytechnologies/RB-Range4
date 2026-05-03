# Incident Report — CLD01-M05
## PUL Cloud IAM Console — Broken Access Control Exposes AD LDAP Credentials
**IR Reference:** INREP-CLD01-M05-20241115
**Incident Type:** Broken Access Control / Privilege Escalation leading to AD Pivot
**Affected System:** cld-iam (11.0.2.50) | PUL Cloud IAM Console v1.0
**Severity:** CRITICAL | **Confidentiality Impact:** CRITICAL | **Integrity Impact:** HIGH

---

## 1. Incident Summary

The PUL Cloud IAM Console contains a Broken Access Control (BAC) vulnerability in the integration export API endpoint. The application enforces access restrictions only at the UI layer (hiding buttons for non-admin users) without server-side role verification. An attacker authenticated as the `cloud-iam-svc` service account (iam_user role) bypassed the UI restriction by directly calling `GET /api/v1/integrations/int-ad-corp-001/export`, which returned the full Active Directory integration configuration including the LDAP bind account credentials (`svc_ldap:Ld@pB1nd#2025!`), domain information (`cyberange.local`, DC: 33.55.55.137), and a reference to the SRV08-WEB admin panel. This completes the cloud zone attack chain and enables pivot into the corporate Active Directory environment.

---

## 2. Timeline

| Time (UTC) | Event |
|---|---|
| T+00:00 | Attacker POSTs to /api/v1/auth/login with cloud-iam-svc:IAm@CLD!2025 → JWT token issued |
| T+00:08 | GET /api/v1/integrations — integration list enumerated, int-ad-corp-001 discovered |
| T+00:14 | GET /api/v1/integrations/int-ad-corp-001/export — **BAC exploited, AD credentials exfiltrated** |
| T+00:20 | LDAP bind test to 33.55.55.137 — svc_ldap credentials confirmed valid |
| T+00:35 | Attacker navigates to 33.55.55.129/admin/ (SRV08-WEB) — LDAP Passback initiated |
| T+00:42 | **AD range pivot achieved — svc_ldap creds captured via passback → RNG-AD-01 begins** |

---

## 3. Root Cause

The Flask application implements a `@require_auth` decorator to verify JWT token validity, but lacks a `@require_role` decorator for sensitive endpoints. The `/export` route:

```python
# VULNERABLE:
@app.route("/api/v1/integrations/<integration_id>/export")
@require_auth  # Only checks token is valid, not what role the user has
def export_integration(integration_id):
    return jsonify(AD_INTEGRATION)  # Returns full config including bind_password
```

The developer assumed the UI layer (hiding the Export button from iam_user accounts) was sufficient access control. This is a textbook Broken Access Control vulnerability (OWASP A01:2021).

A secondary contributing factor: sensitive credentials (LDAP bind password) are stored directly in the application configuration rather than in a dedicated secrets manager, meaning any path to the export endpoint immediately yields plaintext credentials.

---

## 4. Impact Assessment

| Component | Impact | Details |
|---|---|---|
| M5 cld-iam | CRITICAL | Full AD integration config including bind password exported |
| Active Directory (cyberange.local) | CRITICAL | svc_ldap account compromised → AD range kill chain begins |
| SRV08-WEB (33.55.55.129) | HIGH | Admin panel used as LDAP Passback vector |
| All cloud zone machines M1-M5 | HIGH | Complete attack chain confirmed — requires end-to-end rotation |

---

## 5. Recommendations

1. **Immediate:** Rotate svc_ldap in AD; rotate cloud-iam-svc in IAM Console
2. **Immediate:** Restrict SRV08-WEB /admin/ to internal management IPs only
3. **Short-term:** Fix BAC — add `@require_role("iam_admin")` to all export/admin endpoints
4. **Short-term:** Move svc_ldap credentials from app config to Vault/Secrets Manager
5. **Long-term:** Implement API security testing (authorization tests) in CI pipeline
6. **Long-term:** Adopt server-side access control framework — never rely on UI-only restrictions
7. **Architecture:** Conduct end-to-end credential chain review for all inter-service credentials

---

## 6. Lessons Learned

This case demonstrates that the cloud zone kill chain (M1→M5) requires a single misconfiguration or vulnerability at each step — but each step feeds the next. A breach at M1 (SSRF) does not directly threaten AD, but when chained with five subsequent weaknesses it does. Defense-in-depth must treat every cloud service credential as a potential pivot, not just internet-facing endpoints. The BAC finding here mirrors OWASP A01:2021 findings common in real enterprise API audits — missing server-side authorization checks on endpoints where only the UI restricts access.

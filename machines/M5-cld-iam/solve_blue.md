# Solve Guide — Blue Team
## RNG-CLD-01 | M5 — cld-iam | Broken Access Control Detection & Response

## Detection

### 1. Application Audit Log — API Access Anomaly

The IAM console logs all API calls with role information:

```bash
grep "API_CALL" /var/log/pul-cloud/iam.log | grep "int-ad-corp-001" | tail -20
```

A legitimate admin export looks like:
```
2024-11-15 11:20:00 [INFO] API_CALL|path=/api/v1/integrations/int-ad-corp-001/export|user=iam-admin|role=iam_admin|src=10.10.10.5|status=200
```

An attacker call looks like:
```
2024-11-15 11:42:17 [WARNING] API_CALL|path=/api/v1/integrations/int-ad-corp-001/export|user=cloud-iam-svc|role=iam_user|src=33.55.55.136|status=200
```

**Indicator:** `role=iam_user` accessing an admin-gated endpoint. This should be a 403 — a 200 means the access control is broken.

### 2. Detect the Broken Access Control Pattern

Enumerate all API calls where role=iam_user hit endpoints that return sensitive data:
```bash
grep "API_CALL" /var/log/pul-cloud/iam.log | \
    grep "role=iam_user" | \
    grep -E "/export|/credentials|/secrets|/config" | \
    grep "status=200"
```

Any results here indicate broken access control exploitation.

### 3. LDAP Passback Detection (on AD side)

Once `svc_ldap` credentials are used against SRV08-WEB and the attacker changes the LDAP server IP, the Domain Controller logs a failed bind from SRV08-WEB's IP to an external address. Monitor DC Security Event ID 4625 (failed logon) with source IPs outside the AD zone. Also monitor SRV08-WEB IIS logs for POST requests to the LDAP settings page from unexpected source IPs.

## Containment

```bash
# 1. Revoke the cloud-iam-svc JWT (rotate the JWT secret to invalidate all tokens)
# In /opt/pul-cloud-iam/app.py, change JWT_SECRET to a new random value
JWT_SECRET=$(python3 -c "import secrets; print(secrets.token_hex(32))")
sed -i "s/JWT_SECRET = .*/JWT_SECRET = \"${JWT_SECRET}\"/" /opt/pul-cloud-iam/app.py
systemctl restart pul-cloud-iam

# 2. Change cloud-iam-svc password immediately
# Edit USERS dict in app.py and update password hash
# Also rebuild M4 platform-svc image without hardcoded CLOUD_IAM_PASS

# 3. Rotate svc_ldap password in AD immediately
# (On DC) net user svc_ldap NewLdapB1nd#2025! /domain
# Then update bind_password in M5 IAM config

# 4. Force-expire all active sessions:
systemctl restart pul-cloud-iam
```

## Remediation — Fix the Broken Access Control

The root cause is in `/opt/pul-cloud-iam/app.py` at the `/api/v1/integrations/<id>/export` route. The route is decorated with `@login_required` (checks JWT is valid) but NOT with `@admin_required` (checks role=iam_admin):

```python
# VULNERABLE (current):
@app.route("/api/v1/integrations/<integration_id>/export")
@login_required          # Only checks: is token valid?
def export_integration(integration_id):
    return jsonify(AD_INTEGRATION[integration_id])  # No role check

# FIXED:
@app.route("/api/v1/integrations/<integration_id>/export")
@login_required
@admin_required          # Checks: role == 'iam_admin'
def export_integration(integration_id):
    return jsonify(AD_INTEGRATION[integration_id])
```

Additional hardening:
1. Add rate limiting on sensitive API endpoints (`flask-limiter`)
2. Log and alert on any 403 → 200 role escalation patterns
3. Implement API response filtering — never return `bind_password` in plaintext; reference a secrets manager path instead
4. Conduct a full API authorization review (OWASP API Security — API1:2023 Broken Object Level Authorization, API5:2023 Broken Function Level Authorization)
5. Store AD bind credentials in Vault, not in app config files

## Blue Team Checklist
- [ ] Unauthorized export API call confirmed in IAM audit log (role=iam_user, status=200)
- [ ] Source IP and user account identified
- [ ] JWT secret rotated → all active sessions invalidated
- [ ] cloud-iam-svc password changed (+ M4 image rebuilt)
- [ ] svc_ldap password rotated in AD + M5 config updated
- [ ] @admin_required decorator added to export endpoint
- [ ] SRV08-WEB LDAP config checked for tampered server IP
- [ ] DC audit logs reviewed for unauthorized LDAP activity
- [ ] Full API authorization audit initiated

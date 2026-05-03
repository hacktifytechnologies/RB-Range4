# Solve Guide — Blue Team
## RNG-CLD-01 | M1 — cld-webapp | SSRF Detection & Response
**MITRE Defend:** DE.CM-001 (Monitor network traffic), DE.AE-002 (Anomaly detection)

---

## Detection Approach

### 1. Application Log Analysis

The portal logs all URL Health Checker requests to `/var/log/pul-cloud/portal.log`. An SSRF attack against IMDS produces entries like:

```bash
sudo grep "URL_CHECK" /var/log/pul-cloud/portal.log
```

A successful IMDS SSRF chain looks like:
```
2024-11-15 11:04:22 [WARNING] URL_CHECK|src=33.55.55.136|url=http://169.254.169.254/latest/meta-data/|user=cloud-dev
2024-11-15 11:04:39 [WARNING] URL_CHECK|src=33.55.55.136|url=http://169.254.169.254/latest/meta-data/iam/|user=cloud-dev
2024-11-15 11:04:51 [WARNING] URL_CHECK|src=33.55.55.136|url=http://169.254.169.254/latest/meta-data/iam/security-credentials/|user=cloud-dev
2024-11-15 11:05:03 [WARNING] URL_CHECK|src=33.55.55.136|url=http://169.254.169.254/latest/meta-data/iam/security-credentials/pul-cloud-role|user=cloud-dev
```

The final entry above constitutes a credential theft event.

```bash
# Automated detection query — flag any URL_CHECK hitting 169.254.x.x:
grep "URL_CHECK" /var/log/pul-cloud/portal.log | grep "169\.254\."

# Also check for other internal targets:
grep "URL_CHECK" /var/log/pul-cloud/portal.log | \
    grep -E "(10\.|172\.16\.|192\.168\.|127\.|169\.254\.)"
```

### 2. IMDS Hit Detection

The IMDS simulator also logs every request:
```bash
sudo grep "IMDS_HIT" /var/log/pul-cloud/imds.log
```

An SSRF attempt shows the IMDS requests arriving from `127.0.0.1` (the Flask app requesting on behalf of the attacker), not from the attacker's IP directly:
```
2024-11-15 11:05:03 [WARNING] IMDS_HIT|src=127.0.0.1|path=/latest/meta-data/iam/security-credentials/pul-cloud-role
```

**Indicator:** IMDS requests from `127.0.0.1` should be very rare outside automated bootstrap. Any hit on `/iam/security-credentials/` from localhost is a high-confidence SSRF.

### 3. Network-Level Detection (if NIDS deployed)

Snort/Suricata rule to detect SSRF targeting IMDS:
```
alert http any any -> any any (msg:"SSRF IMDS credential theft attempt"; 
  content:"169.254.169.254"; http_client_body; 
  content:"/iam/security-credentials"; http_uri; 
  classtype:credential-access; sid:9000001; rev:1;)
```

---

## Forensic Investigation

### Determine Attacker Entry Point
```bash
# What credential authenticated before the SSRF?
grep "LOGIN_OK" /var/log/pul-cloud/portal.log | grep "$(date +%Y-%m-%d)"

# Cross-reference the source IP
grep "11:04" /var/log/pul-cloud/portal.log | grep -v favicon
```

### Establish Full Timeline
```bash
# All portal events from attacker IP (replace with actual IP)
ATTACKER_IP="33.55.55.136"
grep "${ATTACKER_IP}" /var/log/pul-cloud/portal.log | sort
```

### Confirm Credential Exfiltration
If the `URL_CHECK` log shows the response was printed to the attacker's browser, the `SecretAccessKey` was exfiltrated. Check M2 MinIO access logs immediately:
```bash
# On M2 — look for access from the attacker IP using AKIAPUL2024CLDSVC01
journalctl -u pul-minio --since "2024-11-15 11:00:00" | grep "AKIAPUL2024CLDSVC01"
```

---

## Containment

```bash
# 1. Immediately block attacker IP at firewall
ufw insert 1 deny from 33.55.55.136 comment "SSRF attacker — incident block"

# 2. Kill the URL Health Checker route temporarily
# Comment out the /tools/url-check route in /opt/pul-cloud-portal/app.py
# and restart the service
sudo systemctl restart pul-cloud-portal

# 3. Revoke the exposed API key
# Remove "pul-cloud-dev-aK8x2mP9!2024" from API_KEYS dict in app.py

# 4. Rotate MinIO credentials on M2 immediately — they're now compromised
# (AccessKeyId: AKIAPUL2024CLDSVC01 / SecretAccessKey: pULcLd/S3cr3t2024/K3y!)
```

---

## Remediation

**Fix 1 — Block SSRF at the application level (primary):**
```python
# In /opt/pul-cloud-portal/app.py, add before the requests.get() call:
import ipaddress, urllib.parse

SSRF_BLOCKED_RANGES = [
    ipaddress.ip_network("169.254.0.0/16"),   # Link-local (IMDS)
    ipaddress.ip_network("127.0.0.0/8"),       # Loopback
    ipaddress.ip_network("10.0.0.0/8"),        # RFC1918
    ipaddress.ip_network("172.16.0.0/12"),     # RFC1918
    ipaddress.ip_network("192.168.0.0/16"),    # RFC1918
]

def is_ssrf_blocked(url):
    try:
        host = urllib.parse.urlparse(url).hostname
        ip = ipaddress.ip_address(socket.gethostbyname(host))
        return any(ip in net for net in SSRF_BLOCKED_RANGES)
    except Exception:
        return True  # Block on resolution failure

if is_ssrf_blocked(target_url):
    result = "[Error] This URL is blocked for security reasons."
```

**Fix 2 — IMDSv2 (token-required requests):**
If deploying on a real cloud, enable IMDSv2 which requires a PUT request with a session token header before GET requests are served. SSRF attacks using simple GET cannot fetch IMDSv2 tokens.

**Fix 3 — Principle of least privilege on IAM role:**
The `pul-cloud-role` IAM role should only grant access to S3 buckets this instance genuinely needs — not bucket-owner-level credentials that also work as MinIO root credentials.

**Fix 4 — Rotate all affected credentials:**
- MinIO root credentials (AccessKeyId: AKIAPUL2024CLDSVC01)
- Developer portal API key (pul-cloud-dev-aK8x2mP9!2024)
- Review all downstream access using the stolen key (M2, M3, M4, M5)

---

## Blue Team Checklist
- [ ] SSRF to 169.254.x.x detected in portal logs
- [ ] IMDS hit from 127.0.0.1 confirmed in IMDS logs
- [ ] Source IP and user account identified
- [ ] MinIO credentials rotated
- [ ] Portal API key revoked
- [ ] SSRF mitigation deployed to app code
- [ ] Downstream impact assessment on M2-M5 chain initiated

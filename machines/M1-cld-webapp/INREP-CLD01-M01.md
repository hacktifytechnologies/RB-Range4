# Incident Report — CLD01-M01
## PUL Cloud Developer Portal SSRF — IAM Credential Theft
**IR Reference:** INREP-CLD01-M01-20241115  
**Incident Type:** Cloud Credential Theft via SSRF  
**Affected System:** cld-webapp (11.0.2.10) | PUL Cloud Developer Portal v2.4.1  
**Discovery Method:** Purple Team Exercise — Operation GRIDFALL  
**Severity:** HIGH | **Confidentiality Impact:** HIGH | **Integrity Impact:** LOW

---

## 1. Incident Summary

A Server-Side Request Forgery (SSRF) vulnerability in the PUL Cloud Developer Portal's URL Health Checker feature allowed an authenticated attacker to reach the Cloud Instance Metadata Service (IMDS) at the link-local address `169.254.169.254`. By querying the IAM credentials endpoint of the IMDS, the attacker retrieved the `pul-cloud-role` IAM credentials associated with the cloud instance, including the root `AccessKeyId` and `SecretAccessKey` used for the platform's object storage service (MinIO, M2).

---

## 2. Timeline

| Time (UTC) | Event |
|---|---|
| T+00:00 | Attacker authenticates to portal using cloud_api_key from upstream Dev Zone compromise |
| T+02:14 | First URL Health Checker request: `http://169.254.169.254/latest/meta-data/` |
| T+02:31 | Request to `/latest/meta-data/iam/` — IAM path enumerated |
| T+02:47 | Request to `/latest/meta-data/iam/security-credentials/` — role name discovered: `pul-cloud-role` |
| T+03:01 | Request to `/latest/meta-data/iam/security-credentials/pul-cloud-role` — **credentials stolen** |
| T+05:30 | Attacker begins using AccessKeyId against M2 MinIO storage |

---

## 3. Root Cause

The URL Health Checker feature in `/opt/pul-cloud-portal/app.py` (route `/tools/url-check`) makes an outbound HTTP request using Python's `requests` library with no URL validation, allowlist, or blocklist. The `169.254.0.0/16` link-local range used by cloud IMDS services is reachable from the server process without restriction.

```python
# Vulnerable code (simplified):
resp = req.get(target_url, timeout=5, allow_redirects=True)
```

No controls exist on:
- Target IP range (link-local, loopback, RFC1918 all accessible)
- HTTP schema (file://, gopher:// also potentially accessible)
- Response data logging or filtering

---

## 4. Impact Assessment

| Component | Impact | Details |
|---|---|---|
| M1 cld-webapp | HIGH | SSRF attack vector — portal itself not otherwise compromised |
| M2 cld-storage | HIGH | MinIO root credentials stolen — all buckets accessible |
| M3 cld-k8s | HIGH | K8s kubeconfig in public M2 bucket — token exposed |
| M4 cld-registry | HIGH | Registry credentials readable via M3 K8s secrets |
| M5 cld-iam | HIGH | IAM svc creds in M4 image → AD integration config |
| AD Range | CRITICAL | Full pivot chain leads to Domain Admin via AdminSDHolder |

---

## 5. Recommendations

1. **Immediate:** Rotate AKIAPUL2024CLDSVC01 credentials across all services
2. **Short-term:** Implement SSRF allowlist in URL Health Checker (`https://target-monitoring-domain.com` only)
3. **Short-term:** Enable IMDSv2 (token-required IMDS) on all cloud instances
4. **Long-term:** Remove developer-facing URL fetch tools from production portals
5. **Long-term:** Separate IAM roles — instance credentials must not be equivalent to storage root credentials
6. **Architecture:** The cloud range's single IAM role grants excessive permissions; implement per-service roles with least privilege

---

## 6. Lessons Learned

The SSRF → IMDS credential theft pattern (mirroring the CapitalOne 2019 breach) demonstrates that internal metadata services present a critical attack surface in cloud environments. Developer convenience features (URL health checkers, webhook testers) frequently become SSRF vectors when URL validation is absent. IMDSv2 adoption and SSRF-aware coding practices are the primary mitigations.

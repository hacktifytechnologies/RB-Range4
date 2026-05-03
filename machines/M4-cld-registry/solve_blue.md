# Solve Guide — Blue Team
## RNG-CLD-01 | M4 — cld-registry | Container Credential Hygiene & Detection

## Detection

### 1. Registry Access Logs
The distribution/registry logs all API access to stdout (captured by journald):

```bash
journalctl -u pul-registry | grep "GET /v2/pul-cloud/platform-svc" | tail -20

# Flag these specific access patterns — they indicate image inspection without pull:
# GET /v2/_catalog        → repository enumeration
# GET /v2/.../manifests/  → manifest inspection
# GET /v2/.../blobs/<sha> → blob/layer download
```

A complete SSRF-free inspection session (no docker pull) looks like:
```
GET /v2/_catalog 200
GET /v2/pul-cloud/platform-svc/tags/list 200
GET /v2/pul-cloud/platform-svc/manifests/latest 200
GET /v2/pul-cloud/platform-svc/blobs/sha256:<config_digest> 200  ← config blob = creds
```

### 2. Detect Credential Patterns in Images

Run a static analysis scan to identify the issue proactively:

```bash
# Using Trivy (if installed):
trivy image --no-progress 11.0.2.40:5000/pul-cloud/platform-svc:latest \
    --security-checks secret

# Manual config blob inspection:
CONFIG=$(curl -su "registry-admin:Reg!stry@CLD2024" \
    -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
    http://11.0.2.40:5000/v2/pul-cloud/platform-svc/manifests/latest \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['config']['digest'])")

curl -su "registry-admin:Reg!stry@CLD2024" \
    http://11.0.2.40:5000/v2/pul-cloud/platform-svc/blobs/${CONFIG} \
    | python3 -c "import sys,json; [print(e) for e in json.load(sys.stdin)['config']['Env']]"
# If PASS= or PASSWORD= or SECRET= appear → alert
```

### 3. Unauthorized Access Detection
Any access using credentials other than known CI/CD service accounts is suspicious:

```bash
# Registry htpasswd only has registry-admin
# Any successful auth from unexpected IPs is a breach indicator
journalctl -u pul-registry | grep "200" | grep -v "^.*11\.0\." | head -20
```

## Containment

```bash
# 1. Rotate registry credentials immediately
cd /opt/pul-registry
htpasswd -Bb auth/htpasswd registry-admin 'NewReg!stry@CLD2025!'
systemctl restart pul-registry

# 2. Update K8s registry-creds secret on M3 with new password
kubectl create secret generic registry-creds \
    --from-literal=username=registry-admin \
    --from-literal=password='NewReg!stry@CLD2025!' \
    --from-literal=registry=11.0.2.40:5000 \
    -n pul-cloud --dry-run=client -o yaml | kubectl apply -f -

# 3. Rebuild the platform-svc image WITHOUT the hardcoded ENV vars
# Remove ENV CLOUD_IAM_USER and ENV CLOUD_IAM_PASS from Dockerfile
# Inject at runtime via K8s Secret instead
```

## Remediation

1. **Never bake credentials into container image ENV variables** — they persist in every layer of every manifest forever. Use K8s Secrets mounted as environment variables at runtime.
2. Implement a CI gate that fails builds containing credential patterns in ENV (`secretlint`, `detect-secrets`, `trufflehog --docker`).
3. Enforce image signing (cosign/Notary) so tampered images with injected creds can be detected.
4. Use a registry with fine-grained access control (Harbor) — the current distribution/distribution binary does not support per-repository permissions.
5. Scrub all existing image tags that contain credentials: rebuild, retag, delete old tags.

## Blue Team Checklist
- [ ] Registry access logs reviewed — unauthorized blob download confirmed
- [ ] Registry credentials rotated (htpasswd on M4 + K8s secret on M3)
- [ ] CLOUD_IAM_PASS rotated on M5 (IAm@CLD!2025 → new value)
- [ ] platform-svc image rebuilt without hardcoded ENV credentials
- [ ] Old image tags (latest, 2.4.0, 2.4.1) deleted from registry
- [ ] Secret scanning gate added to CI/CD pipeline
- [ ] Trivy/Grype scan scheduled for all registry images weekly

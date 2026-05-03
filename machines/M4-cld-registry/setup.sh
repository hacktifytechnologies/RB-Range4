#!/usr/bin/env bash
# =============================================================================
# RNG-CLD-01 | M4 — cld-registry | setup.sh
# Challenge: Sensitive Credentials Hardcoded in Container Image ENV
# Network:   11.0.2.40
# Port:      5000 (OCI Distribution Registry v2)
# Pivot In:  registry-admin:Reg!stry@CLD2024 from M3 K8s Secret
# Pivot Out: CLOUD_IAM_USER + CLOUD_IAM_PASS in image config ENV
#            → cloud-iam-svc:IAm@CLD!2025 @ 11.0.2.50:8080 (M5)
# MITRE:     T1552.001 (Credentials in Files — container image layers)
# Ubuntu 22.04 LTS | run deps.sh first. No Docker daemon required.
# =============================================================================
set -euo pipefail
if [[ $EUID -ne 0 ]]; then echo "[!] Must be run as root." >&2; exit 1; fi
command -v registry >/dev/null 2>&1 || { echo "[!] Run deps.sh first." >&2; exit 1; }

REGISTRY_HOME="/opt/pul-registry"
REGISTRY_DATA="${REGISTRY_HOME}/data"
REGISTRY_CONF="${REGISTRY_HOME}/config"
LOG_DIR="/var/log/pul-cloud"
SERVICE_NAME="pul-registry"
REGISTRY_PORT=5000

REG_USER="registry-admin"
REG_PASS="Reg!stry@CLD2024"

echo "============================================================"
echo "  RNG-CLD-01 | M4-cld-registry | Challenge Setup"
echo "  Prabal Urja Limited — Operation GRIDFALL"
echo "============================================================"

mkdir -p "${REGISTRY_DATA}" "${REGISTRY_CONF}" "${LOG_DIR}"
HOST_IP=$(hostname -I | awk '{print $1}')

# ── Create htpasswd ───────────────────────────────────────────────────────────
echo "[*] Creating registry authentication..."
htpasswd -Bbn "${REG_USER}" "${REG_PASS}" > "${REGISTRY_CONF}/htpasswd"

# ── Registry configuration ────────────────────────────────────────────────────
cat > "${REGISTRY_CONF}/config.yml" << EOF
version: 0.1
log:
  level: info
  fields:
    service: pul-cloud-registry
storage:
  filesystem:
    rootdirectory: ${REGISTRY_DATA}
  delete:
    enabled: true
auth:
  htpasswd:
    realm: pul-cloud-registry
    path: ${REGISTRY_CONF}/htpasswd
http:
  addr: 0.0.0.0:${REGISTRY_PORT}
  headers:
    X-Content-Type-Options: [nosniff]
    X-Frame-Options: [DENY]
EOF

# ── Systemd service ───────────────────────────────────────────────────────────
cat > /etc/systemd/system/${SERVICE_NAME}.service << EOF
[Unit]
Description=PUL Cloud Container Registry (M4)
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/registry serve ${REGISTRY_CONF}/config.yml
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${SERVICE_NAME}

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "${SERVICE_NAME}" --quiet
systemctl restart "${SERVICE_NAME}"

echo "[*] Waiting for registry to become ready..."
for i in $(seq 1 20); do
    if curl -sf -u "${REG_USER}:${REG_PASS}" \
            "http://127.0.0.1:${REGISTRY_PORT}/v2/" -o /dev/null 2>/dev/null; then
        echo "[+] Registry ready after ${i}s."
        break
    fi
    [[ $i -eq 20 ]] && { echo "[!] Registry not ready." >&2; journalctl -u "${SERVICE_NAME}" -n 20 --no-pager >&2; exit 1; }
    sleep 1
done

# ── Create and push OCI image via Registry v2 API ────────────────────────────
# No Docker daemon needed — we craft a valid OCI image using Python and
# push it directly via the Registry v2 HTTP API.
echo "[*] Creating and pushing pul-cloud/platform-svc image..."

python3 << 'PYEOF'
import json, hashlib, gzip, io, tarfile, sys
import requests

REGISTRY  = "http://127.0.0.1:5000"
AUTH      = ("registry-admin", "Reg!stry@CLD2024")
REPO      = "pul-cloud/platform-svc"
TAG       = "latest"

def sha256hex(data: bytes) -> str:
    return "sha256:" + hashlib.sha256(data).hexdigest()

def push_blob(data: bytes, content_type: str = "application/octet-stream") -> tuple:
    """Upload a blob to the registry. Returns (digest, size)."""
    digest = sha256hex(data)
    size   = len(data)

    # Check if blob already exists
    r = requests.head(f"{REGISTRY}/v2/{REPO}/blobs/{digest}", auth=AUTH)
    if r.status_code == 200:
        return digest, size

    # Initiate upload
    r = requests.post(f"{REGISTRY}/v2/{REPO}/blobs/uploads/", auth=AUTH)
    if r.status_code not in (202, 201):
        print(f"[!] Failed to initiate blob upload: {r.status_code} {r.text}", file=sys.stderr)
        sys.exit(1)
    upload_url = r.headers["Location"]

    # Complete upload in one PUT (monolithic)
    sep = "&" if "?" in upload_url else "?"
    r = requests.put(
        f"{upload_url}{sep}digest={digest}",
        data=data,
        auth=AUTH,
        headers={
            "Content-Type": content_type,
            "Content-Length": str(size),
        }
    )
    if r.status_code not in (201, 204):
        print(f"[!] Blob upload failed: {r.status_code} {r.text}", file=sys.stderr)
        sys.exit(1)
    return digest, size

# ── Layer: tar.gz containing config file with credentials ────────────────────
layer_buf = io.BytesIO()
with tarfile.open(fileobj=layer_buf, mode="w:gz") as tar:
    def add_dir(name):
        ti = tarfile.TarInfo(name)
        ti.type = tarfile.DIRTYPE
        ti.mode = 0o755
        tar.addfile(ti)

    def add_file(name, content: bytes, mode=0o644):
        ti = tarfile.TarInfo(name)
        ti.size = len(content)
        ti.mode = mode
        tar.addfile(ti, io.BytesIO(content))

    add_dir("opt")
    add_dir("opt/app")
    add_dir("opt/app/config")

    # ── THE VULNERABILITY: credentials hardcoded in config file ───────────────
    config_env = b"""# PUL Cloud Platform Service Configuration
# Auto-generated by Terraform provisioner v1.2.1
# WARNING: Do not edit manually — managed by cloud-ops automation

PLATFORM_ENV=production
PLATFORM_VERSION=2.4.1-release
CLOUD_REGION=in-south-1

# Cloud IAM Service Integration
# TODO(cloud-ops#841): Move to Vault secret — CURRENTLY HARDCODED
CLOUD_IAM_URL=http://11.0.2.50:8080
CLOUD_IAM_USER=cloud-iam-svc
CLOUD_IAM_PASS=IAm@CLD!2025

# Storage
STORAGE_ENDPOINT=http://11.0.2.20:9000
STORAGE_BUCKET=pul-cloud-internal

# Feature flags
ENABLE_METRICS=true
ENABLE_AUDIT_LOG=true
LOG_LEVEL=info
"""
    add_file("opt/app/config/.env", config_env)
    add_file("opt/app/config/README.txt",
             b"PUL Cloud Platform Service\nVersion 2.4.1\nDo not distribute.\n")

layer_data = layer_buf.getvalue()

# Compute uncompressed diff_id (sha256 of the uncompressed tar)
raw_tar_buf = io.BytesIO()
with tarfile.open(fileobj=raw_tar_buf, mode="w") as tar:
    def add_dir2(name):
        ti = tarfile.TarInfo(name); ti.type = tarfile.DIRTYPE; ti.mode = 0o755; tar.addfile(ti)
    def add_file2(name, content, mode=0o644):
        ti = tarfile.TarInfo(name); ti.size = len(content); ti.mode = mode; tar.addfile(ti, io.BytesIO(content))
    add_dir2("opt"); add_dir2("opt/app"); add_dir2("opt/app/config")
    add_file2("opt/app/config/.env", config_env)
    add_file2("opt/app/config/README.txt", b"PUL Cloud Platform Service\nVersion 2.4.1\nDo not distribute.\n")
diff_id = sha256hex(raw_tar_buf.getvalue())

layer_digest, layer_size = push_blob(
    layer_data,
    "application/vnd.docker.image.rootfs.diff.tar.gzip"
)
print(f"[+] Layer pushed: {layer_digest[:32]}... ({layer_size} bytes)")

# ── Config blob (contains ENV vars — the primary attack vector) ───────────────
config_json = {
    "architecture": "amd64",
    "os": "linux",
    "created": "2024-11-15T10:00:00.000000000Z",
    "author": "cloud-ops@prabalurja.in",
    "config": {
        "Env": [
            "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
            "PLATFORM_ENV=production",
            "PLATFORM_VERSION=2.4.1-release",
            "CLOUD_REGION=in-south-1",
            "CLOUD_IAM_URL=http://11.0.2.50:8080",
            "CLOUD_IAM_USER=cloud-iam-svc",
            "CLOUD_IAM_PASS=IAm@CLD!2025",
            "STORAGE_ENDPOINT=http://11.0.2.20:9000",
        ],
        "WorkingDir": "/opt/app",
        "Cmd": ["/bin/sh", "-c", "python3 /opt/app/server.py"],
        "Labels": {
            "maintainer": "cloud-ops@prabalurja.in",
            "version": "2.4.1",
            "build-date": "2024-11-15",
        }
    },
    "rootfs": {
        "type": "layers",
        "diff_ids": [diff_id]
    },
    "history": [
        {
            "created": "2024-11-15T10:00:00.000000000Z",
            "created_by": "/bin/sh -c #(nop) ADD file:platform-base.tar.gz /",
            "comment": "buildkit.dockerfile.v0"
        },
        {
            "created": "2024-11-15T10:01:00.000000000Z",
            "created_by": "/bin/sh -c #(nop) ENV CLOUD_IAM_USER=cloud-iam-svc CLOUD_IAM_PASS=IAm@CLD!2025",
            "empty_layer": True
        }
    ]
}
config_data = json.dumps(config_json, separators=(",", ":")).encode()
config_digest, config_size = push_blob(
    config_data,
    "application/vnd.docker.container.image.v1+json"
)
print(f"[+] Config pushed: {config_digest[:32]}... ({config_size} bytes)")

# ── Manifest ──────────────────────────────────────────────────────────────────
manifest = {
    "schemaVersion": 2,
    "mediaType": "application/vnd.docker.distribution.manifest.v2+json",
    "config": {
        "mediaType": "application/vnd.docker.container.image.v1+json",
        "size": config_size,
        "digest": config_digest
    },
    "layers": [
        {
            "mediaType": "application/vnd.docker.image.rootfs.diff.tar.gzip",
            "size": layer_size,
            "digest": layer_digest
        }
    ]
}
manifest_data = json.dumps(manifest, indent=2).encode()

r = requests.put(
    f"{REGISTRY}/v2/{REPO}/manifests/{TAG}",
    data=manifest_data,
    auth=AUTH,
    headers={"Content-Type": "application/vnd.docker.distribution.manifest.v2+json"}
)
if r.status_code in (200, 201):
    manifest_digest = r.headers.get("Docker-Content-Digest", sha256hex(manifest_data))
    print(f"[+] Manifest pushed: {REPO}:{TAG}")
    print(f"    Manifest digest: {manifest_digest}")
    print(f"    Image ENV contains: CLOUD_IAM_USER=cloud-iam-svc, CLOUD_IAM_PASS=IAm@CLD!2025")
else:
    print(f"[!] Manifest push failed: {r.status_code} {r.text}", file=sys.stderr)
    sys.exit(1)

print("[+] Image pul-cloud/platform-svc:latest successfully pushed to registry.")
PYEOF

# ── Firewall ──────────────────────────────────────────────────────────────────
if command -v ufw &>/dev/null; then
    ufw allow "${REGISTRY_PORT}/tcp" comment "Registry M4 challenge" >/dev/null 2>&1 || true
fi

# ── Verification ──────────────────────────────────────────────────────────────
echo ""
echo "[*] Running verification..."

# Service
systemctl is-active --quiet "${SERVICE_NAME}" && \
    echo "[✓] Registry service: running" || echo "[✗] Registry not running" >&2

# Auth works
AUTH_OK=$(curl -sf -u "${REG_USER}:${REG_PASS}" \
    "http://127.0.0.1:${REGISTRY_PORT}/v2/" -o /dev/null -w "%{http_code}" 2>/dev/null || echo "000")
[[ "${AUTH_OK}" == "200" ]] && echo "[✓] Registry auth: OK" || echo "[✗] Registry auth failed" >&2

# Catalog shows our image
CATALOG=$(curl -sf -u "${REG_USER}:${REG_PASS}" \
    "http://127.0.0.1:${REGISTRY_PORT}/v2/_catalog" 2>/dev/null || echo '{}')
echo "${CATALOG}" | grep -q "pul-cloud/platform-svc" && \
    echo "[✓] Image in catalog: pul-cloud/platform-svc" || echo "[✗] Image not in catalog" >&2

# Manifest has config with ENV creds
MANIFEST=$(curl -sf -u "${REG_USER}:${REG_PASS}" \
    "http://127.0.0.1:${REGISTRY_PORT}/v2/pul-cloud/platform-svc/manifests/latest" \
    -H "Accept: application/vnd.docker.distribution.manifest.v2+json" 2>/dev/null || echo '{}')
CONFIG_DIGEST=$(echo "${MANIFEST}" | python3 -c \
    "import sys,json; print(json.load(sys.stdin).get('config',{}).get('digest','FAIL'))" \
    2>/dev/null || echo "FAIL")

if [[ "${CONFIG_DIGEST}" != "FAIL" && -n "${CONFIG_DIGEST}" ]]; then
    CONFIG=$(curl -sf -u "${REG_USER}:${REG_PASS}" \
        "http://127.0.0.1:${REGISTRY_PORT}/v2/pul-cloud/platform-svc/blobs/${CONFIG_DIGEST}" \
        2>/dev/null | python3 -c \
        "import sys,json; envs=json.load(sys.stdin).get('config',{}).get('Env',[]); [print(e) for e in envs if 'IAM_PASS' in e]" \
        2>/dev/null || echo "")
    if echo "${CONFIG}" | grep -q "IAm@CLD"; then
        echo "[✓] Credential in image config ENV confirmed: CLOUD_IAM_PASS=IAm@CLD!2025"
    else
        echo "[✗] Credential not found in image ENV" >&2
    fi
fi

echo ""
echo "============================================================"
echo "  M4 Setup Complete — cld-registry"
echo "  Registry URL : http://${HOST_IP}:${REGISTRY_PORT}"
echo "  Login        : ${REG_USER} / ${REG_PASS}"
echo ""
echo "  CHALLENGE:"
echo "  # List repositories"
echo "  curl -u '${REG_USER}:${REG_PASS}' http://${HOST_IP}:${REGISTRY_PORT}/v2/_catalog"
echo ""
echo "  # Get manifest and find config digest"
echo "  curl -u '${REG_USER}:${REG_PASS}' \\"
echo "    http://${HOST_IP}:${REGISTRY_PORT}/v2/pul-cloud/platform-svc/manifests/latest \\"
echo "    -H 'Accept: application/vnd.docker.distribution.manifest.v2+json'"
echo ""
echo "  # Download config blob (contains ENV with credentials)"
echo "  curl -u '${REG_USER}:${REG_PASS}' \\"
echo "    http://${HOST_IP}:${REGISTRY_PORT}/v2/pul-cloud/platform-svc/blobs/<config-digest>"
echo ""
echo "  PIVOT CREDENTIAL:"
echo "  CLOUD_IAM_USER=cloud-iam-svc"
echo "  CLOUD_IAM_PASS=IAm@CLD!2025"
echo "  → http://11.0.2.50:8080 (M5 Cloud IAM)"
echo "  MITRE: T1552.001 (Credentials in Container Image)"
echo "============================================================"

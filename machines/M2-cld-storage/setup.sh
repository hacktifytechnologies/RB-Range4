#!/usr/bin/env bash
# =============================================================================
# RNG-CLD-01 | M2 — cld-storage | setup.sh
# Challenge: Misconfigured Cloud Object Storage (S3-compatible) — Public Bucket
# Network:   11.0.2.20
# Ports:     9000 (MinIO S3 API), 9001 (MinIO Console)
# Pivot In:  AccessKeyId + SecretAccessKey from M1 IMDS SSRF
# Pivot Out: k8s/cloud-ci-kubeconfig.yaml → K8s API (M3 11.0.2.30:6443)
# MITRE:     T1530 (Data from Cloud Storage Object)
# Ubuntu 22.04 LTS | run deps.sh first.
# =============================================================================
set -euo pipefail
if [[ $EUID -ne 0 ]]; then echo "[!] Must be run as root." >&2; exit 1; fi
command -v minio >/dev/null 2>&1 || { echo "[!] Run deps.sh first." >&2; exit 1; }

MINIO_USER="minio"
MINIO_HOME="/opt/pul-minio"
MINIO_DATA="${MINIO_HOME}/data"
LOG_DIR="/var/log/pul-cloud"
SERVICE_NAME="pul-minio"
MINIO_API_PORT=9000
MINIO_CONSOLE_PORT=9001

# Credentials matching M1 IMDS response
ACCESS_KEY="AKIAPUL2024CLDSVC01"
SECRET_KEY='pULcLd/S3cr3t2024/K3y!'

echo "============================================================"
echo "  RNG-CLD-01 | M2-cld-storage | Challenge Setup"
echo "  Prabal Urja Limited — Operation GRIDFALL"
echo "============================================================"

mkdir -p "${MINIO_DATA}" "${LOG_DIR}"

# ── System user ───────────────────────────────────────────────────────────────
if ! id -u "${MINIO_USER}" &>/dev/null; then
    useradd --system --no-create-home --shell /usr/sbin/nologin \
            --home "${MINIO_HOME}" "${MINIO_USER}"
fi
chown -R "${MINIO_USER}:${MINIO_USER}" "${MINIO_HOME}"

# ── Systemd service ───────────────────────────────────────────────────────────
cat > /etc/systemd/system/${SERVICE_NAME}.service << EOF
[Unit]
Description=PUL Cloud Object Storage — MinIO (M2)
After=network.target

[Service]
Type=simple
User=${MINIO_USER}
Group=${MINIO_USER}
WorkingDirectory=${MINIO_HOME}
ExecStart=/usr/local/bin/minio server ${MINIO_DATA} \
    --address :${MINIO_API_PORT} \
    --console-address :${MINIO_CONSOLE_PORT}
Restart=always
RestartSec=5
Environment=MINIO_ROOT_USER=${ACCESS_KEY}
Environment=MINIO_ROOT_PASSWORD=${SECRET_KEY}
Environment=MINIO_VOLUMES=${MINIO_DATA}
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${SERVICE_NAME}

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "${SERVICE_NAME}" --quiet
systemctl restart "${SERVICE_NAME}"

echo "[*] Waiting for MinIO to become ready..."
for i in $(seq 1 30); do
    if curl -sf "http://127.0.0.1:${MINIO_API_PORT}/minio/health/live" -o /dev/null 2>/dev/null; then
        echo "[+] MinIO ready after ${i}s."
        break
    fi
    [[ $i -eq 30 ]] && { echo "[!] MinIO not ready after 30s." >&2; journalctl -u "${SERVICE_NAME}" -n 20 --no-pager >&2; exit 1; }
    sleep 1
done

# ── Configure MinIO via mc ────────────────────────────────────────────────────
echo "[*] Configuring MinIO buckets and policies..."
export MC_HOST_pulminio="http://${ACCESS_KEY}:${SECRET_KEY}@127.0.0.1:${MINIO_API_PORT}"

# Create the vulnerable public bucket
mc mb pulminio/pul-cloud-backups --ignore-existing 2>/dev/null || true
mc mb pulminio/pul-cloud-internal --ignore-existing 2>/dev/null || true

# MISCONFIGURATION: make pul-cloud-backups bucket publicly listable + readable
mc anonymous set public pulminio/pul-cloud-backups 2>/dev/null || \
    mc policy set public pulminio/pul-cloud-backups 2>/dev/null || true

# ── Create challenge artefact: kubeconfig ────────────────────────────────────
echo "[*] Seeding challenge artefacts..."
HOST_IP=$(hostname -I | awk '{print $1}')
TMPDIR=$(mktemp -d)

# Decoy files in backups bucket
cat > "${TMPDIR}/README.txt" << 'EOF'
PUL Cloud Backups — Automated Storage
======================================
This bucket contains automated backups from PUL Cloud infrastructure.
Classification: INTERNAL — Authorised Access Only

Contents:
  backups/   — Database and config backups
  configs/   — Infrastructure configuration exports  
  k8s/       — Kubernetes cluster artefacts
  logs/      — Aggregated platform logs

Contact: cloud-ops@prabalurja.in
EOF

cat > "${TMPDIR}/cluster-info.txt" << 'EOF'
PUL Cloud Kubernetes Cluster — in-south-1
==========================================
Cluster Endpoint  : https://11.0.2.30:6443
Cluster Version   : v1.28.4+k3s2
Namespace         : pul-cloud
Registry          : 11.0.2.40:5000
IAM Endpoint      : http://11.0.2.50:8080

Service Accounts:
  cloud-ci-runner  — CI/CD pipeline (read-only, pul-cloud ns)
  platform-svc     — Platform service account (restricted)

Note: Kubeconfig for cloud-ci-runner available in k8s/ directory.
EOF

cat > "${TMPDIR}/db-backup-2024-11-14.sql.enc" << 'EOF'
ENCRYPTED_BACKUP_V2:AES256-GCM
NOT_FOR_DIRECT_USE — Decryption key managed by Cloud KMS
Contact cloud-ops@prabalurja.in for access
EOF

cat > "${TMPDIR}/config-backup-2024-11-10.tar.gz.note" << 'EOF'
Archive: config-backup-2024-11-10.tar.gz
Size: 14.2 MB (encrypted)
Contents: Infrastructure configuration (nginx, vault, ansible)
Encryption: AES-256-GCM (KMS key: pul-cloud-backup-key-2024)
EOF

# THE KEY ARTEFACT: kubeconfig with static token matching M3's K3s setup
cat > "${TMPDIR}/cloud-ci-kubeconfig.yaml" << 'EOF'
# PUL Cloud Kubernetes Cluster — CI/CD Runner Kubeconfig
# Service Account: cloud-ci-runner (pul-cloud namespace)
# Generated: 2024-11-15 by cloud-ops automation
# WARNING: This file contains a service account token. Treat as secret.
apiVersion: v1
kind: Config
preferences: {}
clusters:
- name: pul-cloud
  cluster:
    server: https://11.0.2.30:6443
    insecure-skip-tls-verify: true
contexts:
- name: pul-cloud
  context:
    cluster: pul-cloud
    namespace: pul-cloud
    user: cloud-ci-runner
current-context: pul-cloud
users:
- name: cloud-ci-runner
  user:
    token: pul-cloud-ci-runner-token-2024gridfall
EOF

cat > "${TMPDIR}/deployment-notes.txt" << 'EOF'
Deployment Notes — 2024-11-15
==============================
- K3s cluster upgraded to v1.28.4+k3s2
- registry-creds secret rotated (see k8s/cloud-ci-kubeconfig.yaml for access)
- Monitoring stack deployed to pul-cloud namespace
- TODO: Rotate cloud-ci-runner token (scheduled 2025-Q1)
EOF

# Upload all artefacts
mc cp "${TMPDIR}/README.txt"                    pulminio/pul-cloud-backups/README.txt
mc cp "${TMPDIR}/cluster-info.txt"              pulminio/pul-cloud-backups/k8s/cluster-info.txt
mc cp "${TMPDIR}/cloud-ci-kubeconfig.yaml"      pulminio/pul-cloud-backups/k8s/cloud-ci-kubeconfig.yaml
mc cp "${TMPDIR}/db-backup-2024-11-14.sql.enc"  pulminio/pul-cloud-backups/backups/db-backup-2024-11-14.sql.enc
mc cp "${TMPDIR}/config-backup-2024-11-10.tar.gz.note" pulminio/pul-cloud-backups/backups/config-backup-note.txt
mc cp "${TMPDIR}/deployment-notes.txt"          pulminio/pul-cloud-backups/configs/deployment-notes.txt

# Internal bucket (private — for context/decoy)
cat > "${TMPDIR}/internal-readme.txt" << 'EOF'
Internal cloud configurations — NOT PUBLIC
Access via cloud-ops credentials only.
EOF
mc cp "${TMPDIR}/internal-readme.txt" pulminio/pul-cloud-internal/README.txt

rm -rf "${TMPDIR}"
echo "[+] Artefacts uploaded."

# ── Firewall ──────────────────────────────────────────────────────────────────
if command -v ufw &>/dev/null; then
    ufw allow "${MINIO_API_PORT}/tcp"     comment "MinIO API M2 challenge"     >/dev/null 2>&1 || true
    ufw allow "${MINIO_CONSOLE_PORT}/tcp" comment "MinIO Console M2 challenge" >/dev/null 2>&1 || true
fi

# ── Verification ──────────────────────────────────────────────────────────────
echo ""
echo "[*] Running verification..."

# 1. Service running
systemctl is-active --quiet "${SERVICE_NAME}" && \
    echo "[✓] MinIO service: running" || echo "[✗] MinIO not running" >&2

# 2. Bucket listing (public — no auth needed)
LISTING=$(curl -sf "http://127.0.0.1:${MINIO_API_PORT}/pul-cloud-backups?list-type=2" 2>/dev/null || echo "FAIL")
if echo "${LISTING}" | grep -q "cloud-ci-kubeconfig"; then
    echo "[✓] Public bucket listing works — kubeconfig visible"
else
    echo "[~] Bucket listing check inconclusive (may need anonymous policy)"
fi

# 3. Direct download works
KUBE_TEST=$(curl -sf "http://127.0.0.1:${MINIO_API_PORT}/pul-cloud-backups/k8s/cloud-ci-kubeconfig.yaml" 2>/dev/null || echo "FAIL")
if echo "${KUBE_TEST}" | grep -q "pul-cloud-ci-runner-token"; then
    echo "[✓] Kubeconfig accessible — contains correct K8s token"
else
    echo "[✗] Kubeconfig not accessible" >&2
fi

echo ""
echo "============================================================"
echo "  M2 Setup Complete — cld-storage"
echo "  MinIO S3 API : http://${HOST_IP}:${MINIO_API_PORT}"
echo "  MinIO Console: http://${HOST_IP}:${MINIO_CONSOLE_PORT}"
echo "  Access Key   : ${ACCESS_KEY}"
echo "  Secret Key   : ${SECRET_KEY}"
echo ""
echo "  CHALLENGE:"
echo "  # Using AWS CLI with M1 stolen credentials:"
echo "  AWS_ACCESS_KEY_ID=${ACCESS_KEY} \\"
echo "  AWS_SECRET_ACCESS_KEY='${SECRET_KEY}' \\"
echo "  aws s3 ls s3://pul-cloud-backups/ --endpoint-url http://${HOST_IP}:${MINIO_API_PORT}"
echo ""
echo "  # Or direct curl (public bucket):"
echo "  curl 'http://${HOST_IP}:${MINIO_API_PORT}/pul-cloud-backups?list-type=2'"
echo "  curl http://${HOST_IP}:${MINIO_API_PORT}/pul-cloud-backups/k8s/cloud-ci-kubeconfig.yaml"
echo ""
echo "  PIVOT CREDENTIAL:"
echo "  K8s token: pul-cloud-ci-runner-token-2024gridfall"
echo "  → kubectl against M3 at 11.0.2.30:6443"
echo "  MITRE: T1530 (Data from Cloud Storage Object)"
echo "============================================================"

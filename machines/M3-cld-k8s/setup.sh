#!/usr/bin/env bash
# =============================================================================
# RNG-CLD-01 | M3 — cld-k8s | setup.sh
# Challenge: Misconfigured Kubernetes RBAC — Over-Privileged Service Account
#            exposes container registry credentials via K8s Secrets API
# Network:   11.0.2.30
# Ports:     6443 (K8s API — TLS)
# Pivot In:  K8s SA token (pul-cloud-ci-runner-token-2024gridfall) from M2 kubeconfig
# Pivot Out: registry-creds secret → registry-admin:Reg!stry@CLD2024 @ 11.0.2.40:5000
# MITRE:     T1613 (Container and Resource Discovery)
#            T1552.007 (Container API — Kubernetes Secrets)
# Ubuntu 22.04 LTS | run deps.sh first.
# =============================================================================
set -euo pipefail
if [[ $EUID -ne 0 ]]; then echo "[!] Must be run as root." >&2; exit 1; fi
command -v k3s >/dev/null 2>&1 || { echo "[!] Run deps.sh first." >&2; exit 1; }

K3S_CONFIG_DIR="/etc/rancher/k3s"
LOG_DIR="/var/log/pul-cloud"
STATIC_TOKEN="pul-cloud-ci-runner-token-2024gridfall"

echo "============================================================"
echo "  RNG-CLD-01 | M3-cld-k8s | Challenge Setup"
echo "  Prabal Urja Limited — Operation GRIDFALL"
echo "============================================================"

mkdir -p "${K3S_CONFIG_DIR}" "${LOG_DIR}"

# ── Static token file (predictable, matches M2 kubeconfig) ───────────────────
# Format: token,username,uid,groups
# This gives the cloud-ci-runner user a known, static bearer token.
# The RBAC below grants this user read on secrets in pul-cloud namespace.
echo "[*] Creating static token auth file..."
cat > "${K3S_CONFIG_DIR}/tokens.csv" << EOF
${STATIC_TOKEN},cloud-ci-runner,cloud-ci-runner-uid,pul-cloud-devs
EOF
chmod 600 "${K3S_CONFIG_DIR}/tokens.csv"

# ── K3s configuration: enable static token auth, disable unused components ────
echo "[*] Writing K3s server configuration..."
cat > "${K3S_CONFIG_DIR}/config.yaml" << 'EOF'
# K3s server config — PUL Cloud Cluster
kube-apiserver-arg:
- "token-auth-file=/etc/rancher/k3s/tokens.csv"
disable:
- traefik
- servicelb
- local-storage
write-kubeconfig-mode: "0600"
EOF

# ── Start K3s ─────────────────────────────────────────────────────────────────
echo "[*] Starting K3s..."
systemctl enable k3s --quiet
systemctl restart k3s

echo "[*] Waiting for K3s API server to become ready (up to 90s)..."
export KUBECONFIG="/etc/rancher/k3s/k3s.yaml"
READY=0
for i in $(seq 1 45); do
    if kubectl get nodes --no-headers 2>/dev/null | grep -q "Ready"; then
        READY=1
        echo "[+] K3s cluster ready after ${i}×2s."
        break
    fi
    sleep 2
done
[[ $READY -eq 0 ]] && { echo "[!] K3s not ready after 90s." >&2; journalctl -u k3s -n 30 --no-pager >&2; exit 1; }

# ── Apply all K8s resources ───────────────────────────────────────────────────
echo "[*] Applying Kubernetes resources (namespace, RBAC, secrets)..."
kubectl apply -f - << 'MANIFESTS'
# ─── Namespace ────────────────────────────────────────────────────────────────
apiVersion: v1
kind: Namespace
metadata:
  name: pul-cloud
  labels:
    environment: production
    managed-by: terraform
    owner: cloud-ops

---
# ─── ServiceAccount ───────────────────────────────────────────────────────────
apiVersion: v1
kind: ServiceAccount
metadata:
  name: cloud-ci-runner
  namespace: pul-cloud
  annotations:
    description: "CI/CD pipeline service account — read-only access to pul-cloud namespace"
    created-by: "terraform/cloud-iam-v1.2.1"
    last-rotated: "2024-09-12"

---
# ─── RBAC Role: misconfigured — grants secrets access ─────────────────────────
# VULNERABILITY: The cloud-ci-runner role grants access to read Secrets.
# In a properly configured cluster, CI runners should NOT have secrets access.
# This allows an attacker with the CI runner token to read registry credentials.
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: cloud-ci-runner-role
  namespace: pul-cloud
  annotations:
    description: "CI runner permissions — overprivileged (should not include secrets)"
rules:
- apiGroups: [""]
  resources: ["pods", "services", "endpoints", "configmaps"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  # MISCONFIGURATION: CI runner should NOT need to read Secrets
  resources: ["secrets"]
  verbs: ["get", "list"]
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets"]
  verbs: ["get", "list"]

---
# ─── RoleBinding: binds static-token user to the role ─────────────────────────
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: cloud-ci-runner-binding
  namespace: pul-cloud
subjects:
# Bind both the service account AND the static token user (cloud-ci-runner)
- kind: ServiceAccount
  name: cloud-ci-runner
  namespace: pul-cloud
- kind: User
  name: cloud-ci-runner
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: cloud-ci-runner-role
  apiGroup: rbac.authorization.k8s.io

---
# ─── THE PIVOT SECRET: Registry credentials ───────────────────────────────────
# Players read this to obtain credentials for M4 (Container Registry)
apiVersion: v1
kind: Secret
metadata:
  name: registry-creds
  namespace: pul-cloud
  annotations:
    description: "Container registry credentials — auto-rotated quarterly"
    registry-url: "11.0.2.40:5000"
    created-by: "terraform/registry-v1.0.0"
    last-rotated: "2024-09-01"
    next-rotation: "2025-03-01"
type: Opaque
stringData:
  username: "registry-admin"
  password: "Reg!stry@CLD2024"
  registry: "11.0.2.40:5000"
  docker-config: |
    {"auths":{"11.0.2.40:5000":{"username":"registry-admin","password":"Reg!stry@CLD2024","auth":"cmVnaXN0cnktYWRtaW46UmVnIXN0cnlAQ0xEMjAyNA=="}}}

---
# ─── Decoy Secret: DB credentials (not useful for pivot) ──────────────────────
apiVersion: v1
kind: Secret
metadata:
  name: db-creds
  namespace: pul-cloud
  annotations:
    description: "Application database credentials"
type: Opaque
stringData:
  host: "203.0.2.15"
  port: "5432"
  database: "pul_cloud_app"
  username: "cloud_app_ro"
  password: "DbReadOnly@CLD2024!"

---
# ─── Decoy ConfigMap ──────────────────────────────────────────────────────────
apiVersion: v1
kind: ConfigMap
metadata:
  name: platform-config
  namespace: pul-cloud
data:
  cloud-region: "in-south-1"
  storage-endpoint: "http://11.0.2.20:9000"
  iam-endpoint: "http://11.0.2.50:8080"
  log-level: "info"
  platform-version: "2.4.1"

---
# ─── Decoy Deployment (shows realistic cluster usage) ─────────────────────────
apiVersion: apps/v1
kind: Deployment
metadata:
  name: platform-api
  namespace: pul-cloud
  labels:
    app: platform-api
spec:
  replicas: 0
  selector:
    matchLabels:
      app: platform-api
  template:
    metadata:
      labels:
        app: platform-api
    spec:
      serviceAccountName: cloud-ci-runner
      containers:
      - name: platform-api
        image: 11.0.2.40:5000/pul-cloud/platform-svc:latest
        ports:
        - containerPort: 8080
        envFrom:
        - secretRef:
            name: registry-creds
        - configMapRef:
            name: platform-config
MANIFESTS

echo "[+] K8s resources applied."

# ── Verify static token authentication works ──────────────────────────────────
echo "[*] Verifying static token authentication..."
sleep 3
HOST_IP=$(hostname -I | awk '{print $1}')

TOKEN_AUTH=$(curl -sk \
    -H "Authorization: Bearer ${STATIC_TOKEN}" \
    "https://127.0.0.1:6443/api/v1/namespaces/pul-cloud/secrets" \
    2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('kind','FAIL'))" \
    2>/dev/null || echo "FAIL")

if [[ "${TOKEN_AUTH}" == "SecretList" ]]; then
    echo "[✓] Static token auth works — cloud-ci-runner can list secrets"
else
    echo "[~] Token auth check inconclusive (cluster may still be initialising)"
fi

# Check registry-creds is readable
REGCRED_CHECK=$(curl -sk \
    -H "Authorization: Bearer ${STATIC_TOKEN}" \
    "https://127.0.0.1:6443/api/v1/namespaces/pul-cloud/secrets/registry-creds" \
    2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('metadata',{}).get('name','FAIL'))" \
    2>/dev/null || echo "FAIL")

[[ "${REGCRED_CHECK}" == "registry-creds" ]] && \
    echo "[✓] registry-creds secret accessible with CI runner token" || \
    echo "[~] Secret check inconclusive"

# ── Firewall ──────────────────────────────────────────────────────────────────
if command -v ufw &>/dev/null; then
    ufw allow 6443/tcp comment "K3s API M3 challenge" >/dev/null 2>&1 || true
fi

echo ""
echo "============================================================"
echo "  M3 Setup Complete — cld-k8s"
echo "  K8s API   : https://${HOST_IP}:6443"
echo "  Namespace : pul-cloud"
echo ""
echo "  CHALLENGE (with kubeconfig from M2):"
echo "  export KUBECONFIG=./cloud-ci-kubeconfig.yaml"
echo "  kubectl get secrets -n pul-cloud"
echo "  kubectl get secret registry-creds -n pul-cloud -o jsonpath='{.data.password}' | base64 -d"
echo ""
echo "  OR with raw curl:"
echo "  curl -sk -H 'Authorization: Bearer ${STATIC_TOKEN}' \\"
echo "    https://${HOST_IP}:6443/api/v1/namespaces/pul-cloud/secrets/registry-creds"
echo ""
echo "  PIVOT CREDENTIAL:"
echo "  registry-admin : Reg!stry@CLD2024  →  11.0.2.40:5000"
echo "  MITRE: T1552.007 / T1613"
echo "============================================================"

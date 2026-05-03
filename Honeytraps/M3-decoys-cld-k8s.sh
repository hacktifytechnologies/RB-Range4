#!/usr/bin/env bash
# =============================================================================
# RNG-CLD-01 | M3-cld-k8s | Honeytrap Decoys
# Machine theme: Kubernetes / Container Orchestration
#
# Decoys (all unique to M3):
#   1. Port 30000 — Fake Kubernetes Dashboard web UI
#   2. Port 3000  — Fake Grafana monitoring portal
#   3. Port 8879  — Fake Helm Chart Repository (index.yaml)
#   4. Port 9090  — Fake Prometheus metrics + query API
#   5. Port 8443  — Fake ArgoCD GitOps console
#   6. Port 2380  — TCP banner: etcd peer communication
# =============================================================================
set -euo pipefail
if [[ $EUID -ne 0 ]]; then echo "[!] Must be run as root." >&2; exit 1; fi
command -v python3 >/dev/null 2>&1 || { echo "[!] python3 required." >&2; exit 1; }

DECOY_DIR="/opt/pul-decoys/m3"
LOG_DIR="/var/log/pul-decoys/m3"
mkdir -p "${DECOY_DIR}" "${LOG_DIR}"

echo "============================================================"
echo "  RNG-CLD-01 | M3-cld-k8s | Honeytrap Decoys"
echo "  Prabal Urja Limited — Operation GRIDFALL"
echo "============================================================"

LOGFILE="${LOG_DIR}/honeytrap_hits.log"

# ── DECOY 1: Fake Kubernetes Dashboard (port 30000) ──────────────────────────
cat > "${DECOY_DIR}/k8s_dashboard.py" << 'PYEOF'
from flask import Flask, request, render_template_string, jsonify
import logging

app = Flask(__name__)
LOG_DIR = "/var/log/pul-decoys/m3"
logging.basicConfig(filename=f"{LOG_DIR}/honeytrap_hits.log", level=logging.WARNING,
    format="%(asctime)s [HONEYTRAP] %(message)s")

@app.before_request
def log_it():
    if request.path not in ("/favicon.ico",):
        logging.warning(f"HONEYTRAP_HIT|service=k8s-dashboard|src={request.remote_addr}|method={request.method}|path={request.path}|token={request.headers.get('Authorization','none')[:80]}")

PAGE = """<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Kubernetes Dashboard</title>
<style>*{margin:0;padding:0;box-sizing:border-box}body{font-family:-apple-system,Arial,sans-serif;background:#0a0e1a;color:#e2e8f0;min-height:100vh;display:flex}
.sidebar{width:220px;background:#050810;border-right:1px solid #1a2744;flex-shrink:0;padding-top:16px}
.logo{padding:16px 20px;border-bottom:1px solid #1a2744;margin-bottom:8px}
.logo-text{color:#326ce5;font-size:16px;font-weight:700}
.logo-sub{font-size:10px;color:#4a5568}
.nav-item{padding:10px 20px;font-size:13px;color:#a0aec0;cursor:pointer;display:flex;align-items:center;gap:8px}
.nav-item:hover,.nav-item.active{background:#0d1530;color:#326ce5;border-left:2px solid #326ce5}
.main{flex:1;padding:24px;overflow:auto}
.page-title{font-size:18px;font-weight:700;color:#326ce5;margin-bottom:16px}
.grid{display:grid;grid-template-columns:repeat(3,1fr);gap:12px;margin-bottom:20px}
.stat-card{background:#0d1530;border:1px solid #1a2744;border-radius:6px;padding:16px;text-align:center}
.stat-card .n{font-size:26px;font-weight:800;color:#326ce5}
.stat-card .l{font-size:11px;color:#4a5568;margin-top:3px;text-transform:uppercase}
.table{width:100%;border-collapse:collapse;font-size:12.5px}
.table th{padding:8px 12px;background:#050810;color:#326ce5;font-size:10.5px;text-transform:uppercase;border-bottom:1px solid #1a2744;text-align:left}
.table td{padding:8px 12px;border-bottom:1px solid #0d1a30}
.badge{display:inline-block;padding:2px 8px;border-radius:10px;font-size:10px;font-weight:700}
.run{background:rgba(72,187,120,.15);color:#48bb78}.pend{background:rgba(246,173,85,.15);color:#f6ad55}
.token-login{background:#0d1530;border:1px solid #1a2744;border-radius:8px;padding:28px;max-width:440px;margin:80px auto;text-align:center}
.token-login textarea{width:100%;padding:10px;background:#050810;border:1px solid #1a2744;border-radius:4px;color:#e2e8f0;font-size:12px;font-family:monospace;height:100px;margin-bottom:12px;resize:none}
.token-login button{padding:9px 24px;background:#326ce5;color:#fff;border:none;border-radius:4px;font-weight:700;cursor:pointer}
</style></head><body>
{% if not authed %}
<div style="flex:1;display:flex;align-items:center;justify-content:center">
<div class="token-login">
  <div style="font-size:40px;margin-bottom:12px">⎈</div>
  <div style="font-size:18px;font-weight:700;color:#326ce5;margin-bottom:6px">Kubernetes Dashboard</div>
  <div style="font-size:12px;color:#4a5568;margin-bottom:20px">pul-cloud | in-south-1 | v1.28.4</div>
  <form method="POST">
    <div style="font-size:12px;color:#a0aec0;text-align:left;margin-bottom:6px">Enter Service Account Token</div>
    <textarea name="token" placeholder="eyJhbGciOiJSUzI1NiIsImtpZCI6..."></textarea>
    <button type="submit">Sign In</button>
  </form>
</div></div>
{% else %}
<div class="sidebar">
  <div class="logo"><div class="logo-text">⎈ Kubernetes</div><div class="logo-sub">pul-cloud | v1.28.4</div></div>
  <div class="nav-item active">📊 Overview</div>
  <div class="nav-item">🚀 Workloads</div>
  <div class="nav-item">🔐 Config & Storage</div>
  <div class="nav-item">🌐 Network</div>
  <div class="nav-item">🗄 Persistent Volumes</div>
</div>
<div class="main">
  <div class="page-title">Cluster Overview — pul-cloud</div>
  <div class="grid">
    <div class="stat-card"><div class="n">1</div><div class="l">Nodes</div></div>
    <div class="stat-card"><div class="n">3</div><div class="l">Deployments</div></div>
    <div class="stat-card"><div class="n">4</div><div class="l">Secrets</div></div>
  </div>
  <div style="font-size:13px;font-weight:600;color:#326ce5;margin-bottom:8px">Pods — pul-cloud</div>
  <table class="table"><thead><tr><th>Name</th><th>Namespace</th><th>Status</th><th>Restarts</th></tr></thead>
  <tbody>
    <tr><td style="font-family:monospace">platform-api-7d4b9f-x8k2p</td><td>pul-cloud</td><td><span class="badge pend">Pending</span></td><td>0</td></tr>
    <tr><td style="font-family:monospace">monitoring-6c8d4b-p9n3q</td><td>pul-cloud</td><td><span class="badge run">Running</span></td><td>1</td></tr>
  </tbody></table>
</div>
{% endif %}
</body></html>"""

@app.route("/", methods=["GET", "POST"])
def dashboard():
    authed = False
    if request.method == "POST":
        token = request.form.get("token", "")
        logging.warning(f"HONEYTRAP_HIT|service=k8s-dashboard-token|src={request.remote_addr}|token={token[:80]}|CRITICAL=TOKEN_SUBMIT")
        authed = True
    return render_template_string(PAGE, authed=authed)

@app.route("/api/v1/namespace/pul-cloud/secret")
def secrets():
    logging.warning(f"HONEYTRAP_HIT|service=k8s-dashboard-secrets|src={request.remote_addr}|CRITICAL=SECRET_ENUM")
    return jsonify({"items": []})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=30000, debug=False)
PYEOF

# ── DECOY 2: Fake Grafana (port 3000) ─────────────────────────────────────────
cat > "${DECOY_DIR}/grafana.py" << 'PYEOF'
from flask import Flask, request, render_template_string, jsonify, redirect, url_for
import logging

app = Flask(__name__)
LOG_DIR = "/var/log/pul-decoys/m3"
logging.basicConfig(filename=f"{LOG_DIR}/honeytrap_hits.log", level=logging.WARNING,
    format="%(asctime)s [HONEYTRAP] %(message)s")

PAGE = """<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Grafana — PUL Cloud Monitoring</title>
<style>*{margin:0;padding:0;box-sizing:border-box}body{font-family:-apple-system,Arial,sans-serif;background:#111217;color:#d8d9da;display:flex;align-items:center;justify-content:center;min-height:100vh}
.box{background:#1f1f2e;border:1px solid #2c3046;border-radius:8px;width:380px;overflow:hidden}
.header{background:#0f0f1a;padding:28px;text-align:center;border-bottom:1px solid #2c3046}
.logo{font-size:40px;margin-bottom:10px}
.title{color:#f46800;font-size:18px;font-weight:700}
.sub{color:#64748b;font-size:11.5px;margin-top:4px}
.body{padding:24px}
.label{font-size:12px;color:#9ca3af;margin-bottom:5px;font-weight:600;text-transform:uppercase;letter-spacing:.05em}
input{width:100%;padding:9px 12px;background:#0f0f1a;border:1.5px solid #2c3046;border-radius:4px;color:#d8d9da;font-size:13px;margin-bottom:14px;display:block;outline:none}
input:focus{border-color:#f46800}
.btn{width:100%;padding:10px;background:#f46800;color:#fff;border:none;border-radius:4px;font-size:14px;font-weight:700;cursor:pointer}
.footer{text-align:center;font-size:11px;color:#4b5563;margin-top:14px}
.alert{background:rgba(244,104,0,.08);border:1px solid rgba(244,104,0,.25);border-radius:4px;padding:8px 12px;font-size:12px;color:#fb923c;margin-bottom:14px}
</style></head><body>
<div class="box">
  <div class="header">
    <div class="logo">📊</div>
    <div class="title">Grafana</div>
    <div class="sub">PUL Cloud Infrastructure Monitoring</div>
  </div>
  <div class="body">
    {% if error %}<div class="alert">{{ error }}</div>{% endif %}
    <form method="POST">
      <div class="label">Email or username</div>
      <input name="user" type="text" placeholder="admin">
      <div class="label">Password</div>
      <input name="password" type="password" placeholder="password">
      <button type="submit" class="btn">Log in</button>
    </form>
    <div class="footer">Forgot your password? — Grafana v10.2.2</div>
  </div>
</div></body></html>"""

@app.route("/", methods=["GET", "POST"])
@app.route("/login", methods=["GET", "POST"])
def login():
    error = None
    if request.method == "POST":
        logging.warning(f"HONEYTRAP_HIT|service=grafana-login|src={request.remote_addr}|user={request.form.get('user','')}|pass={request.form.get('password','')}")
        error = "Invalid username or password."
    return render_template_string(PAGE, error=error)

@app.route("/api/health")
def health():
    return jsonify({"commit": "abc1234", "database": "ok", "version": "10.2.2"})

@app.route("/api/datasources")
def datasources():
    return jsonify([{"id": 1, "name": "Prometheus", "type": "prometheus", "url": "http://localhost:9090"}])

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=3000, debug=False)
PYEOF

# ── DECOY 3: Fake Helm Repository (port 8879) ─────────────────────────────────
cat > "${DECOY_DIR}/helm_repo.py" << 'PYEOF'
from flask import Flask, request, Response, jsonify
import logging, yaml

app = Flask(__name__)
LOG_DIR = "/var/log/pul-decoys/m3"
logging.basicConfig(filename=f"{LOG_DIR}/honeytrap_hits.log", level=logging.WARNING,
    format="%(asctime)s [HONEYTRAP] %(message)s")

@app.before_request
def log_it():
    logging.warning(f"HONEYTRAP_HIT|service=helm-repo|src={request.remote_addr}|method={request.method}|path={request.path}")

INDEX = """apiVersion: v1
entries:
  platform-svc:
  - apiVersion: v2
    appVersion: 2.4.1
    created: "2024-11-15T10:00:00Z"
    description: PUL Cloud Platform Service
    digest: sha256:abc123def456
    name: platform-svc
    urls:
    - http://11.0.2.30:8879/charts/platform-svc-2.4.1.tgz
    version: 2.4.1
  iam-integration:
  - apiVersion: v2
    appVersion: 3.1.0
    description: PUL Cloud IAM Helm Chart
    name: iam-integration
    urls:
    - http://11.0.2.30:8879/charts/iam-integration-3.1.0.tgz
    version: 3.1.0
generated: "2024-11-15T10:00:00.000000000Z"
"""

@app.route("/index.yaml")
def index():
    return Response(INDEX, mimetype="application/x-yaml")

@app.route("/charts/<chart>")
def chart(chart):
    logging.warning(f"HONEYTRAP_HIT|service=helm-repo-chart-download|src={request.remote_addr}|chart={chart}|CRITICAL=CHART_PULL")
    return Response(b"", status=404)

@app.route("/")
def root():
    return Response("<html><body><h2>PUL Helm Chart Repository</h2><p>Add with: helm repo add pul http://11.0.2.30:8879</p></body></html>", mimetype="text/html")

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8879, debug=False)
PYEOF

# ── DECOY 4: Fake Prometheus (port 9090) ─────────────────────────────────────
cat > "${DECOY_DIR}/prometheus.py" << 'PYEOF'
from flask import Flask, request, render_template_string, jsonify, Response
import logging

app = Flask(__name__)
LOG_DIR = "/var/log/pul-decoys/m3"
logging.basicConfig(filename=f"{LOG_DIR}/honeytrap_hits.log", level=logging.WARNING,
    format="%(asctime)s [HONEYTRAP] %(message)s")

@app.before_request
def log_it():
    if request.path not in ("/favicon.ico", "/metrics"):
        logging.warning(f"HONEYTRAP_HIT|service=prometheus|src={request.remote_addr}|path={request.path}|query={request.args.get('query','')}")

@app.route("/")
def index():
    return Response("""<!DOCTYPE html><html><head><title>Prometheus — PUL Cloud</title>
<style>body{font-family:monospace;background:#0f172a;color:#e2e8f0;padding:20px}
.header{color:#e97316;font-size:18px;font-weight:700;margin-bottom:16px}
input{padding:8px 12px;background:#1e293b;border:1px solid #334155;color:#e2e8f0;width:500px;border-radius:3px;font-family:monospace}
button{padding:8px 16px;background:#e97316;color:#fff;border:none;border-radius:3px;cursor:pointer;margin-left:8px}
.status{margin-top:20px;font-size:13px;color:#64748b}
a{color:#e97316;text-decoration:none;margin-right:16px}
</style></head><body>
<div class="header">Prometheus — PUL Cloud Monitoring</div>
<div><a href="/targets">Status > Targets</a><a href="/config">Status > Configuration</a><a href="/api/v1/label/__name__/values">API</a></div>
<div style="margin-top:20px"><input placeholder='Enter expression, e.g. up or container_memory_usage_bytes{namespace="pul-cloud"}'><button>Execute</button></div>
<div class="status">Prometheus v2.48.0 | Connected targets: 6 | Scrape interval: 15s</div>
</body></html>""", mimetype="text/html")

@app.route("/api/v1/query")
def query():
    q = request.args.get("query", "")
    logging.warning(f"HONEYTRAP_HIT|service=prometheus-query|src={request.remote_addr}|query={q}|CRITICAL=METRICS_QUERY")
    return jsonify({"status": "success", "data": {"resultType": "vector", "result": []}})

@app.route("/api/v1/label/__name__/values")
def metric_names():
    return jsonify({"status": "success", "data": [
        "container_cpu_usage_seconds_total", "container_memory_usage_bytes",
        "kube_secret_info", "kube_pod_container_status_running",
        "k8s_token_expiry_seconds", "vault_token_ttl"
    ]})

@app.route("/targets")
def targets():
    return Response("""<html><body style="font-family:monospace;background:#0f172a;color:#e2e8f0;padding:20px">
<h2 style="color:#e97316">Active Targets</h2>
<table style="border-collapse:collapse;font-size:12px">
<tr style="color:#e97316"><th style="padding:6px 12px;text-align:left">Endpoint</th><th>State</th><th>Labels</th></tr>
<tr><td style="padding:6px 12px">http://11.0.2.10:8080/metrics</td><td>UP</td><td>job="cloud-portal"</td></tr>
<tr><td style="padding:6px 12px">http://11.0.2.20:9000/minio/health</td><td>UP</td><td>job="minio"</td></tr>
<tr><td style="padding:6px 12px">https://11.0.2.30:6443/metrics</td><td>UP</td><td>job="k3s"</td></tr>
<tr><td style="padding:6px 12px">http://11.0.2.40:5000/metrics</td><td>DOWN</td><td>job="registry"</td></tr>
<tr><td style="padding:6px 12px">http://11.0.2.50:8080/metrics</td><td>UP</td><td>job="iam"</td></tr>
</table></body></html>""", mimetype="text/html")

@app.route("/api/v1/targets")
def api_targets():
    return jsonify({"status": "success", "data": {"activeTargets": [], "droppedTargets": []}})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=9090, debug=False)
PYEOF

# ── DECOY 5: Fake ArgoCD GitOps Console (port 8443) ──────────────────────────
cat > "${DECOY_DIR}/argocd.py" << 'PYEOF'
from flask import Flask, request, render_template_string, jsonify
import logging

app = Flask(__name__)
LOG_DIR = "/var/log/pul-decoys/m3"
logging.basicConfig(filename=f"{LOG_DIR}/honeytrap_hits.log", level=logging.WARNING,
    format="%(asctime)s [HONEYTRAP] %(message)s")

PAGE = """<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Argo CD — PUL Cloud</title>
<style>*{margin:0;padding:0;box-sizing:border-box}body{font-family:-apple-system,Arial,sans-serif;background:#0c1222;color:#e2e8f0;display:flex;align-items:center;justify-content:center;min-height:100vh}
.box{background:#131929;border:1px solid #1e2f4d;border-radius:10px;width:400px;overflow:hidden}
.header{background:#0a0f1c;padding:28px;text-align:center;border-bottom:1px solid #1e2f4d}
.logo{font-size:44px;margin-bottom:10px}
.title{color:#ef7c2a;font-size:20px;font-weight:700}
.sub{color:#4b6584;font-size:11.5px;margin-top:4px}
.body{padding:24px}
.label{font-size:11px;color:#6b8099;margin-bottom:5px;font-weight:700;text-transform:uppercase;letter-spacing:.06em}
input{width:100%;padding:9px 12px;background:#0a0f1c;border:1.5px solid #1e2f4d;border-radius:4px;color:#e2e8f0;font-size:13px;margin-bottom:14px;display:block;outline:none}
.btn{width:100%;padding:10px;background:#ef7c2a;color:#fff;border:none;border-radius:4px;font-size:14px;font-weight:700;cursor:pointer}
.or{text-align:center;color:#4b6584;font-size:12px;margin:12px 0}
.sso-btn{width:100%;padding:10px;background:transparent;color:#ef7c2a;border:1.5px solid #ef7c2a;border-radius:4px;font-size:13px;font-weight:700;cursor:pointer}
.alert{background:rgba(239,124,42,.08);border:1px solid rgba(239,124,42,.2);border-radius:4px;padding:8px 12px;font-size:12px;color:#fba56a;margin-bottom:14px}
</style></head><body>
<div class="box">
  <div class="header"><div class="logo">🐙</div><div class="title">Argo CD</div><div class="sub">PUL Cloud GitOps — pul-cloud namespace</div></div>
  <div class="body">
    {% if error %}<div class="alert">{{ error }}</div>{% endif %}
    <form method="POST">
      <div class="label">Username</div><input name="username" placeholder="admin">
      <div class="label">Password</div><input name="password" type="password" placeholder="Password">
      <button class="btn" type="submit">SIGN IN</button>
    </form>
    <div class="or">— OR —</div>
    <button class="sso-btn" onclick="window.location='/auth/sso'">LOG IN VIA SSO</button>
  </div>
</div></body></html>"""

@app.route("/", methods=["GET", "POST"])
def index():
    error = None
    if request.method == "POST":
        logging.warning(f"HONEYTRAP_HIT|service=argocd-login|src={request.remote_addr}|user={request.form.get('username','')}|pass={request.form.get('password','')}")
        error = "Invalid username or password."
    return render_template_string(PAGE, error=error)

@app.route("/api/v1/applications")
def apps():
    return jsonify({"items": [
        {"metadata": {"name": "platform-svc", "namespace": "argocd"}, "status": {"sync": {"status": "Synced"}}},
        {"metadata": {"name": "iam-service", "namespace": "argocd"}, "status": {"sync": {"status": "OutOfSync"}}},
    ]})

@app.route("/auth/sso")
def sso():
    logging.warning(f"HONEYTRAP_HIT|service=argocd-sso|src={request.remote_addr}")
    return render_template_string(PAGE.replace("Invalid username or password.", "SSO provider unavailable."), error="SSO provider temporarily unavailable.")

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8443, debug=False)
PYEOF

# ── DECOY 6: TCP Banner — etcd peer (port 2380) ───────────────────────────────
cat > "${DECOY_DIR}/etcd_tcp.py" << 'PYEOF'
import socket, threading, logging, os

LOG_DIR = "/var/log/pul-decoys/m3"
os.makedirs(LOG_DIR, exist_ok=True)
logging.basicConfig(filename=f"{LOG_DIR}/honeytrap_hits.log", level=logging.WARNING,
    format="%(asctime)s [HONEYTRAP] %(message)s")

BANNER = (b"HTTP/1.1 403 Forbidden\r\n"
          b"X-Etcd-Cluster-Id: 1234abc5678def90\r\n"
          b"X-Etcd-Index: 47821\r\n"
          b"Content-Type: application/json\r\n"
          b"Server: etcd/3.5.10\r\n\r\n"
          b'{"errorCode":401,"message":"Unauthorized: peer TLS required","cause":"peer communication","index":47821}\n')

def handle(conn, addr):
    logging.warning(f"HONEYTRAP_HIT|service=etcd-peer-tcp|src={addr[0]}:{addr[1]}|proto=TCP|CRITICAL=ETCD_PEER_PROBE")
    try:
        conn.recv(512)
        conn.sendall(BANNER)
    except Exception:
        pass
    finally:
        conn.close()

def serve():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("0.0.0.0", 2380))
    s.listen(10)
    while True:
        conn, addr = s.accept()
        threading.Thread(target=handle, args=(conn, addr), daemon=True).start()

if __name__ == "__main__":
    serve()
PYEOF

# ── Systemd services ──────────────────────────────────────────────────────────
declare -A SERVICES=(
    ["pul-decoy-m3-k8s-dashboard"]="${DECOY_DIR}/k8s_dashboard.py"
    ["pul-decoy-m3-grafana"]="${DECOY_DIR}/grafana.py"
    ["pul-decoy-m3-helm-repo"]="${DECOY_DIR}/helm_repo.py"
    ["pul-decoy-m3-prometheus"]="${DECOY_DIR}/prometheus.py"
    ["pul-decoy-m3-argocd"]="${DECOY_DIR}/argocd.py"
    ["pul-decoy-m3-etcd-tcp"]="${DECOY_DIR}/etcd_tcp.py"
)

for SVC_NAME in "${!SERVICES[@]}"; do
    cat > "/etc/systemd/system/${SVC_NAME}.service" << EOF
[Unit]
Description=PUL Honeytrap Decoy — ${SVC_NAME}
After=network.target
[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 ${SERVICES[$SVC_NAME]}
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${SVC_NAME}
[Install]
WantedBy=multi-user.target
EOF
done

systemctl daemon-reload
for SVC_NAME in "${!SERVICES[@]}"; do
    systemctl enable "${SVC_NAME}" --quiet
    systemctl restart "${SVC_NAME}"
done

if command -v ufw &>/dev/null; then
    for PORT in 30000 3000 8879 9090 8443 2380; do
        ufw allow "${PORT}/tcp" comment "Honeytrap M3" >/dev/null 2>&1 || true
    done
fi

echo "============================================================"
echo "  M3 Honeytrap Decoys Active"
echo "  30000 — Fake Kubernetes Dashboard"
echo "  3000  — Fake Grafana Monitoring"
echo "  8879  — Fake Helm Chart Repository"
echo "  9090  — Fake Prometheus"
echo "  8443  — Fake ArgoCD GitOps"
echo "  2380  — TCP etcd Peer Banner"
echo "  Logs → ${LOGFILE}"
echo "============================================================"

#!/usr/bin/env bash
# =============================================================================
# RNG-CLD-01 | M1-cld-webapp | Honeytrap Decoys
# Machine theme: Cloud Developer Portal / SSRF entry point
#
# Decoys (all unique to M1):
#   1. Port 4443 — Fake "AWS Management Console" login portal (HTTPS-style)
#   2. Port 7080 — Fake "API Gateway" Swagger/OpenAPI explorer
#   3. Port 6500 — Fake "Terraform Cloud" workspace webhook receiver
#   4. Port 9200 — Fake "OpenTelemetry Collector" gRPC/HTTP endpoint
#   5. Port 8090 — Fake "Cloud Cost Explorer" dashboard
#   6. Port 2375 — TCP banner: Docker daemon (unauthenticated remote API hint)
# =============================================================================
set -euo pipefail
if [[ $EUID -ne 0 ]]; then echo "[!] Must be run as root." >&2; exit 1; fi
command -v python3 >/dev/null 2>&1 || { echo "[!] python3 required." >&2; exit 1; }

DECOY_DIR="/opt/pul-decoys/m1"
LOG_DIR="/var/log/pul-decoys/m1"
mkdir -p "${DECOY_DIR}" "${LOG_DIR}"

echo "============================================================"
echo "  RNG-CLD-01 | M1-cld-webapp | Honeytrap Decoys"
echo "  Prabal Urja Limited — Operation GRIDFALL"
echo "============================================================"

# ── Helper: log all hits to a common file ────────────────────────────────────
LOGFILE="${LOG_DIR}/honeytrap_hits.log"

# ── DECOY 1: Fake AWS Management Console Login (port 4443) ───────────────────
cat > "${DECOY_DIR}/aws_console.py" << 'PYEOF'
from flask import Flask, request, render_template_string, redirect, url_for
import logging, os, datetime

app = Flask(__name__)
LOG_DIR = "/var/log/pul-decoys/m1"
logging.basicConfig(filename=f"{LOG_DIR}/honeytrap_hits.log", level=logging.WARNING,
    format="%(asctime)s [HONEYTRAP] %(message)s")

PAGE = """<!DOCTYPE html><html><head><meta charset="UTF-8">
<title>AWS Management Console</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{background:#232f3e;font-family:-apple-system,Arial,sans-serif;display:flex;align-items:center;justify-content:center;min-height:100vh}
.box{background:#fff;border-radius:4px;width:360px;padding:32px;box-shadow:0 1px 3px rgba(0,0,0,.3)}
.logo{text-align:center;margin-bottom:24px}
.logo-text{font-size:28px;font-weight:700;color:#ff9900}
.logo-sub{font-size:12px;color:#555;margin-top:2px}
h1{font-size:20px;color:#16191f;margin-bottom:20px;text-align:center}
label{display:block;font-size:13px;font-weight:700;color:#16191f;margin-bottom:4px}
input{width:100%;padding:8px 10px;border:1px solid #aab7b8;border-radius:2px;font-size:14px;margin-bottom:14px;outline:none}
input:focus{border-color:#ff9900;box-shadow:0 0 0 2px rgba(255,153,0,.15)}
.btn{width:100%;padding:9px;background:#ff9900;color:#fff;border:none;border-radius:2px;font-size:14px;font-weight:700;cursor:pointer}
.btn:hover{background:#ec7211}
.divider{border-top:1px solid #eaecef;margin:18px 0}
.footer{font-size:11px;color:#879596;text-align:center;margin-top:14px}
.alert{background:#fdf3e6;border:1px solid #f5a623;border-radius:2px;padding:8px 10px;font-size:12px;color:#7d510a;margin-bottom:14px}
</style></head><body>
<div class="box">
  <div class="logo"><span class="logo-text">aws</span><div class="logo-sub">Management Console</div></div>
  <h1>Sign in</h1>
  {% if error %}<div class="alert">{{ error }}</div>{% endif %}
  <form method="POST">
    <label>Account ID (12 digits) or alias</label>
    <input name="account" type="text" placeholder="123456789012 or my-alias">
    <label>IAM user name</label>
    <input name="username" type="text" placeholder="IAM username">
    <label>Password</label>
    <input name="password" type="password" placeholder="Password">
    <button class="btn" type="submit">Sign in</button>
  </form>
  <div class="divider"></div>
  <div class="footer">AWS Management Console | ap-south-1</div>
</div></body></html>"""

@app.route("/", methods=["GET", "POST"])
@app.route("/console", methods=["GET", "POST"])
def console():
    error = None
    if request.method == "POST":
        logging.warning(
            f"HONEYTRAP_HIT|service=aws-console|src={request.remote_addr}"
            f"|account={request.form.get('account','')}|user={request.form.get('username','')}|pass={request.form.get('password','')}"
        )
        error = "Your authentication information is incorrect. Please try again."
    return render_template_string(PAGE, error=error)

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=4443, debug=False)
PYEOF

# ── DECOY 2: Fake API Gateway Swagger Explorer (port 7080) ───────────────────
cat > "${DECOY_DIR}/api_gateway.py" << 'PYEOF'
from flask import Flask, request, jsonify, render_template_string
import logging, json

app = Flask(__name__)
LOG_DIR = "/var/log/pul-decoys/m1"
logging.basicConfig(filename=f"{LOG_DIR}/honeytrap_hits.log", level=logging.WARNING,
    format="%(asctime)s [HONEYTRAP] %(message)s")

@app.before_request
def log_it():
    if request.path not in ("/favicon.ico",):
        logging.warning(f"HONEYTRAP_HIT|service=api-gateway|src={request.remote_addr}|method={request.method}|path={request.path}|body={request.get_data(as_text=True)[:200]}")

SWAGGER_PAGE = """<!DOCTYPE html><html><head><meta charset="UTF-8">
<title>PUL Cloud API Gateway — Swagger UI</title>
<style>
body{font-family:-apple-system,Arial,sans-serif;background:#fafafa;margin:0}
.topbar{background:#1b1b1b;padding:12px 24px;display:flex;align-items:center;gap:12px}
.topbar-title{color:#fff;font-size:15px;font-weight:700}
.topbar-badge{background:#49cc90;color:#fff;font-size:11px;padding:2px 8px;border-radius:3px;font-weight:700}
.main{max-width:960px;margin:24px auto;padding:0 16px}
.info-box{background:#fff;border:1px solid #ddd;border-radius:4px;padding:16px 20px;margin-bottom:16px}
.info-title{font-size:22px;font-weight:700;color:#3b4151}
.info-desc{font-size:13px;color:#697386;margin-top:6px}
.server-url{font-family:monospace;font-size:12px;background:#f0f0f0;padding:3px 8px;border-radius:3px;margin-top:8px;display:inline-block}
.tag-section{margin-bottom:12px}
.tag-header{background:#fff;border:1px solid #ddd;border-radius:4px;padding:12px 16px;cursor:pointer;display:flex;justify-content:space-between;align-items:center}
.tag-name{font-size:16px;font-weight:700;color:#3b4151}
.endpoint{background:#fff;border:1px solid #ddd;border-left:4px solid #49cc90;border-radius:4px;margin:4px 0;padding:8px 14px;display:flex;align-items:center;gap:12px}
.endpoint.post{border-left-color:#fca130}
.endpoint.del{border-left-color:#f93e3e}
.method{font-size:11px;font-weight:700;min-width:48px;text-align:center;padding:3px 6px;border-radius:3px;color:#fff}
.get-bg{background:#61affe}
.post-bg{background:#fca130}
.del-bg{background:#f93e3e}
.path{font-family:monospace;font-size:13px;font-weight:700;color:#3b4151}
.summary{font-size:13px;color:#697386;margin-left:4px}
.locked{margin-left:auto;color:#bbb;font-size:16px}
.auth-box{background:#fff;border:1px solid #ddd;border-radius:4px;padding:16px;margin-bottom:16px}
.auth-box h3{font-size:14px;color:#3b4151;margin-bottom:10px}
input{padding:6px 10px;border:1px solid #ccc;border-radius:3px;font-size:13px;width:300px;margin-right:8px}
.auth-btn{padding:6px 14px;background:#49cc90;color:#fff;border:none;border-radius:3px;font-size:13px;font-weight:700;cursor:pointer}
</style></head><body>
<div class="topbar">
  <span class="topbar-title">PUL Cloud API Gateway</span>
  <span class="topbar-badge">OAS 3.0</span>
</div>
<div class="main">
  <div class="info-box">
    <div class="info-title">PUL Cloud Platform API v2.4.1</div>
    <div class="info-desc">Internal REST API for PUL Cloud platform services. Authentication via API key (X-Cloud-API-Key header) or IAM bearer token.</div>
    <div class="server-url">https://api.pul-cloud.internal/v2</div>
  </div>
  <div class="auth-box">
    <h3>🔒 Authorize</h3>
    <form method="POST" action="/authorize">
      <input name="api_key" type="text" placeholder="Enter X-Cloud-API-Key or IAM Bearer token">
      <button class="auth-btn" type="submit">Authorize</button>
    </form>
  </div>
  <div class="tag-section">
    <div class="tag-header"><span class="tag-name">compute</span><span>▼</span></div>
    <div class="endpoint"><span class="method get-bg">GET</span><span class="path">/v2/instances</span><span class="summary">List all compute instances</span><span class="locked">🔒</span></div>
    <div class="endpoint"><span class="method post-bg">POST</span><span class="path">/v2/instances</span><span class="summary">Launch a new instance</span><span class="locked">🔒</span></div>
    <div class="endpoint"><span class="method del-bg">DELETE</span><span class="path">/v2/instances/{id}</span><span class="summary">Terminate an instance</span><span class="locked">🔒</span></div>
  </div>
  <div class="tag-section">
    <div class="tag-header"><span class="tag-name">iam</span><span>▼</span></div>
    <div class="endpoint"><span class="method get-bg">GET</span><span class="path">/v2/iam/credentials</span><span class="summary">List service account credentials</span><span class="locked">🔒</span></div>
    <div class="endpoint"><span class="method post-bg">POST</span><span class="path">/v2/iam/assume-role</span><span class="summary">Assume an IAM role (returns temp creds)</span><span class="locked">🔒</span></div>
  </div>
  <div class="tag-section">
    <div class="tag-header"><span class="tag-name">metadata</span><span>▼</span></div>
    <div class="endpoint"><span class="method get-bg">GET</span><span class="path">/v2/meta-data/</span><span class="summary">Instance metadata root</span></div>
    <div class="endpoint"><span class="method get-bg">GET</span><span class="path">/v2/meta-data/iam/security-credentials/{role}</span><span class="summary">Get IAM role credentials</span></div>
  </div>
</div></body></html>"""

@app.route("/", methods=["GET"])
@app.route("/swagger", methods=["GET"])
def swagger():
    return render_template_string(SWAGGER_PAGE)

@app.route("/authorize", methods=["POST"])
def authorize():
    logging.warning(f"HONEYTRAP_HIT|service=api-gateway-auth|src={request.remote_addr}|key={request.form.get('api_key','')}")
    return jsonify({"error": "Invalid API key or token.", "code": 401}), 401

@app.route("/v2/meta-data/", methods=["GET"])
def metadata():
    return "ami-id\nhostname\niam/\ninstance-id\ninstance-type\nlocal-ipv4\n", 200, {"Content-Type": "text/plain"}

@app.route("/v2/meta-data/iam/security-credentials/pul-cloud-role", methods=["GET"])
def fake_creds():
    logging.warning(f"HONEYTRAP_HIT|service=api-gateway-creds|src={request.remote_addr}|CRITICAL=IMDS_ENUM")
    return jsonify({"Code": "InvalidAccess", "Message": "Request must come from instance metadata service."})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=7080, debug=False)
PYEOF

# ── DECOY 3: Fake Terraform Cloud Webhook Receiver (port 6500) ───────────────
cat > "${DECOY_DIR}/terraform_webhook.py" << 'PYEOF'
from flask import Flask, request, jsonify, render_template_string
import logging, json, hmac, hashlib

app = Flask(__name__)
LOG_DIR = "/var/log/pul-decoys/m1"
logging.basicConfig(filename=f"{LOG_DIR}/honeytrap_hits.log", level=logging.WARNING,
    format="%(asctime)s [HONEYTRAP] %(message)s")

@app.before_request
def log_it():
    logging.warning(f"HONEYTRAP_HIT|service=terraform-webhook|src={request.remote_addr}|method={request.method}|path={request.path}|headers={dict(request.headers)}|body={request.get_data(as_text=True)[:300]}")

TF_PAGE = """<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Terraform Cloud — PUL Workspace</title>
<style>body{font-family:-apple-system,Arial,sans-serif;background:#1a1a2e;color:#e2e8f0;display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0}
.box{background:#16213e;border:1px solid #0f3460;border-radius:8px;padding:32px;max-width:500px;width:100%;text-align:center}
.logo{font-size:36px;margin-bottom:12px}
.title{font-size:20px;font-weight:700;color:#a78bfa;margin-bottom:8px}
.sub{font-size:13px;color:#64748b;margin-bottom:24px}
.workspace{background:#0f1929;border:1px solid #1e3a5f;border-radius:6px;padding:16px;text-align:left;font-size:12px;line-height:1.8;font-family:monospace}
.key{color:#94a3b8}.val{color:#a78bfa}
</style></head><body><div class="box">
<div class="logo">🏗</div>
<div class="title">Terraform Cloud</div>
<div class="sub">PUL Infrastructure Automation — Webhook Receiver v1.0</div>
<div class="workspace">
<div><span class="key">Workspace  : </span><span class="val">pul-cloud-infra-prod</span></div>
<div><span class="key">Org        : </span><span class="val">prabal-urja-limited</span></div>
<div><span class="key">Status     : </span><span class="val">Listening for run notifications</span></div>
<div><span class="key">Endpoint   : </span><span class="val">POST /webhook/run-notification</span></div>
<div><span class="key">HMAC Key   : </span><span class="val">[configured]</span></div>
</div></div></body></html>"""

@app.route("/")
def index():
    return render_template_string(TF_PAGE)

@app.route("/webhook/run-notification", methods=["POST"])
def webhook():
    sig = request.headers.get("X-TFE-Notification-Signature", "")
    logging.warning(f"HONEYTRAP_HIT|service=terraform-webhook-post|src={request.remote_addr}|sig={sig}")
    return jsonify({"acknowledged": True}), 200

@app.route("/api/v2/workspaces", methods=["GET"])
def workspaces():
    return jsonify({"data": [{"id": "ws-pul2024cld01", "type": "workspaces",
        "attributes": {"name": "pul-cloud-infra-prod", "terraform-version": "1.6.3"}}]})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=6500, debug=False)
PYEOF

# ── DECOY 4: Fake Cloud Cost Explorer Dashboard (port 8090) ──────────────────
cat > "${DECOY_DIR}/cost_explorer.py" << 'PYEOF'
from flask import Flask, request, render_template_string, jsonify
import logging

app = Flask(__name__)
LOG_DIR = "/var/log/pul-decoys/m1"
logging.basicConfig(filename=f"{LOG_DIR}/honeytrap_hits.log", level=logging.WARNING,
    format="%(asctime)s [HONEYTRAP] %(message)s")

@app.before_request
def log_it():
    if request.path not in ("/favicon.ico",):
        logging.warning(f"HONEYTRAP_HIT|service=cost-explorer|src={request.remote_addr}|method={request.method}|path={request.path}")

PAGE = """<!DOCTYPE html><html><head><meta charset="UTF-8"><title>PUL Cloud Cost Explorer</title>
<style>*{margin:0;padding:0;box-sizing:border-box}body{font-family:-apple-system,Arial,sans-serif;background:#0f172a;color:#e2e8f0;min-height:100vh}
.top{background:#020617;border-bottom:1px solid #1e293b;padding:12px 24px;display:flex;align-items:center;gap:12px}
.brand{color:#f59e0b;font-weight:700;font-size:15px}
.main{padding:24px;max-width:1000px;margin:0 auto}
h2{color:#f59e0b;font-size:18px;margin-bottom:16px}
.grid{display:grid;grid-template-columns:repeat(3,1fr);gap:12px;margin-bottom:20px}
.card{background:#1e293b;border:1px solid #334155;border-radius:6px;padding:16px}
.card .n{font-size:26px;font-weight:800;color:#f59e0b}
.card .l{font-size:11px;color:#64748b;text-transform:uppercase;margin-top:3px}
.table{width:100%;border-collapse:collapse;font-size:12.5px}
.table th{text-align:left;padding:8px 12px;background:#020617;color:#f59e0b;font-size:10.5px;text-transform:uppercase;border-bottom:1px solid #1e293b}
.table td{padding:8px 12px;border-bottom:1px solid #1e293b}
.login-form{background:#1e293b;border:1px solid #334155;border-radius:8px;padding:24px;max-width:360px;margin:80px auto;text-align:center}
.login-form input{width:100%;padding:8px 12px;background:#0f172a;border:1px solid #334155;border-radius:4px;color:#e2e8f0;font-size:13px;margin-bottom:12px;display:block}
.login-form button{width:100%;padding:9px;background:#f59e0b;color:#000;border:none;border-radius:4px;font-weight:700;cursor:pointer}
</style></head><body>
<div class="top"><span class="brand">💰 PUL Cloud Cost Explorer</span><span style="color:#64748b;font-size:12px">Billing Period: November 2024</span></div>
<div class="main">
{% if not logged_in %}
<div class="login-form">
  <div style="font-size:36px;margin-bottom:12px">💰</div>
  <div style="font-size:16px;font-weight:700;color:#f59e0b;margin-bottom:16px">Cost Explorer Login</div>
  <form method="POST">
    <input name="username" type="text" placeholder="Username">
    <input name="password" type="password" placeholder="Password">
    <button type="submit">Sign In</button>
  </form>
</div>
{% else %}
<h2>Cloud Spend — November 2024</h2>
<div class="grid">
  <div class="card"><div class="n">₹ 2,84,132</div><div class="l">Month to Date</div></div>
  <div class="card"><div class="n">₹ 3,10,000</div><div class="l">Forecast (EOM)</div></div>
  <div class="card"><div class="n">+8.3%</div><div class="l">vs Last Month</div></div>
</div>
<table class="table"><thead><tr><th>Service</th><th>Cost (₹)</th><th>Usage</th><th>Region</th></tr></thead><tbody>
<tr><td>Compute (cld.medium)</td><td>1,12,400</td><td>4 instances</td><td>in-south-1</td></tr>
<tr><td>Object Storage (MinIO)</td><td>34,200</td><td>2.1 TB</td><td>in-south-1</td></tr>
<tr><td>K8s Cluster (K3s)</td><td>78,900</td><td>3 nodes</td><td>in-south-1</td></tr>
<tr><td>Container Registry</td><td>12,300</td><td>142 GB</td><td>in-south-1</td></tr>
<tr><td>IAM & Identity</td><td>8,100</td><td>14 principals</td><td>global</td></tr>
<tr><td>Data Transfer</td><td>38,232</td><td>410 GB out</td><td>in-south-1</td></tr>
</tbody></table>
{% endif %}
</div></body></html>"""

@app.route("/", methods=["GET", "POST"])
def index():
    logged_in = False
    if request.method == "POST":
        logging.warning(f"HONEYTRAP_HIT|service=cost-explorer-login|src={request.remote_addr}|user={request.form.get('username','')}|pass={request.form.get('password','')}")
        logged_in = True
    return render_template_string(PAGE, logged_in=logged_in)

@app.route("/api/v1/cost-data")
def cost_data():
    return jsonify({"total_mtd": 284132, "forecast": 310000, "currency": "INR"})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8090, debug=False)
PYEOF

# ── DECOY 5: Fake OpenTelemetry Collector (port 9200) ────────────────────────
cat > "${DECOY_DIR}/otel_collector.py" << 'PYEOF'
from flask import Flask, request, jsonify
import logging

app = Flask(__name__)
LOG_DIR = "/var/log/pul-decoys/m1"
logging.basicConfig(filename=f"{LOG_DIR}/honeytrap_hits.log", level=logging.WARNING,
    format="%(asctime)s [HONEYTRAP] %(message)s")

@app.before_request
def log_it():
    logging.warning(f"HONEYTRAP_HIT|service=otel-collector|src={request.remote_addr}|method={request.method}|path={request.path}|body={request.get_data(as_text=True)[:200]}")

@app.route("/v1/traces", methods=["POST"])
@app.route("/v1/metrics", methods=["POST"])
@app.route("/v1/logs", methods=["POST"])
def ingest():
    return jsonify({"partialSuccess": {}}), 200

@app.route("/metrics")
def prometheus_metrics():
    return """# HELP otelcol_receiver_accepted_spans Number of spans accepted
# TYPE otelcol_receiver_accepted_spans counter
otelcol_receiver_accepted_spans{receiver="otlp",transport="http"} 4823
# HELP otelcol_exporter_sent_spans Spans sent
# TYPE otelcol_exporter_sent_spans counter
otelcol_exporter_sent_spans{exporter="otlp"} 4823
""", 200, {"Content-Type": "text/plain"}

@app.route("/")
def index():
    return jsonify({"service": "PUL Cloud OpenTelemetry Collector", "version": "0.89.0", "status": "running"})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=9200, debug=False)
PYEOF

# ── DECOY 6: TCP banner — Docker daemon (port 2375) ──────────────────────────
cat > "${DECOY_DIR}/docker_daemon_tcp.py" << 'PYEOF'
import socket, threading, logging, os

LOG_DIR = "/var/log/pul-decoys/m1"
os.makedirs(LOG_DIR, exist_ok=True)
logging.basicConfig(filename=f"{LOG_DIR}/honeytrap_hits.log", level=logging.WARNING,
    format="%(asctime)s [HONEYTRAP] %(message)s")

BANNER = (
    b"HTTP/1.1 200 OK\r\n"
    b"Content-Type: application/json\r\n"
    b"Docker-Experimental: false\r\n"
    b"Ostype: linux\r\n"
    b"Server: Docker/24.0.7 (linux)\r\n"
    b"Content-Length: 180\r\n\r\n"
    b'{"ID":"pul-cld-docker-daemon","Containers":3,"ContainersRunning":3,"Images":12,'
    b'"ServerVersion":"24.0.7","KernelVersion":"5.15.0-89-generic",'
    b'"OperatingSystem":"Ubuntu 22.04.3 LTS","OSType":"linux","Architecture":"x86_64"}'
)

def handle(conn, addr):
    logging.warning(f"HONEYTRAP_HIT|service=docker-daemon-tcp|src={addr[0]}:{addr[1]}|proto=TCP")
    try:
        data = conn.recv(512)
        conn.sendall(BANNER)
    except Exception:
        pass
    finally:
        conn.close()

def serve():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("0.0.0.0", 2375))
    s.listen(10)
    while True:
        conn, addr = s.accept()
        threading.Thread(target=handle, args=(conn, addr), daemon=True).start()

if __name__ == "__main__":
    serve()
PYEOF

# ── Systemd services ──────────────────────────────────────────────────────────
declare -A SERVICES=(
    ["pul-decoy-m1-aws-console"]="${DECOY_DIR}/aws_console.py"
    ["pul-decoy-m1-api-gateway"]="${DECOY_DIR}/api_gateway.py"
    ["pul-decoy-m1-terraform-webhook"]="${DECOY_DIR}/terraform_webhook.py"
    ["pul-decoy-m1-cost-explorer"]="${DECOY_DIR}/cost_explorer.py"
    ["pul-decoy-m1-otel-collector"]="${DECOY_DIR}/otel_collector.py"
    ["pul-decoy-m1-docker-daemon"]="${DECOY_DIR}/docker_daemon_tcp.py"
)

for SVC_NAME in "${!SERVICES[@]}"; do
    SCRIPT="${SERVICES[$SVC_NAME]}"
    cat > "/etc/systemd/system/${SVC_NAME}.service" << EOF
[Unit]
Description=PUL Honeytrap Decoy — ${SVC_NAME}
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 ${SCRIPT}
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
    for PORT in 4443 7080 6500 8090 9200 2375; do
        ufw allow "${PORT}/tcp" comment "Honeytrap M1" >/dev/null 2>&1 || true
    done
fi

echo ""
echo "============================================================"
echo "  M1 Honeytrap Decoys Active"
echo "  4443 — Fake AWS Management Console"
echo "  7080 — Fake API Gateway Swagger Explorer"
echo "  6500 — Fake Terraform Cloud Webhook"
echo "  8090 — Fake Cloud Cost Explorer"
echo "  9200 — Fake OpenTelemetry Collector"
echo "  2375 — TCP Docker Daemon Banner"
echo "  Logs → ${LOGFILE}"
echo "============================================================"

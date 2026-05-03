#!/usr/bin/env bash
# =============================================================================
# RNG-CLD-01 | M1 — cld-webapp | setup.sh
# Challenge: SSRF → Cloud Metadata Service (IMDS) → IAM Credential Theft
# Network:   11.0.2.10
# Ports:     8080 (PUL Cloud Developer Portal — SSRF vulnerable)
#            80   (Cloud Metadata Service at 169.254.169.254)
# Pivot In:  cloud_api_key from Dev Zone M5 AWX job output
# Pivot Out: AccessKeyId + SecretAccessKey → M2 MinIO (11.0.2.20:9000)
# MITRE:     T1552.005 (Cloud Instance Metadata API)
# Ubuntu 22.04 LTS | run deps.sh first.
# =============================================================================
set -euo pipefail
if [[ $EUID -ne 0 ]]; then echo "[!] Must be run as root." >&2; exit 1; fi
command -v python3 >/dev/null 2>&1 || { echo "[!] Run deps.sh first." >&2; exit 1; }

APP_DIR="/opt/pul-cloud-portal"
IMDS_DIR="/opt/pul-imds"
LOG_DIR="/var/log/pul-cloud"
PORTAL_PORT=8080
IMDS_PORT=80
IMDS_IP="169.254.169.254"

echo "============================================================"
echo "  RNG-CLD-01 | M1-cld-webapp | Challenge Setup"
echo "  Prabal Urja Limited — Operation GRIDFALL"
echo "============================================================"

mkdir -p "${APP_DIR}" "${IMDS_DIR}" "${LOG_DIR}"

# ── Add loopback alias for 169.254.169.254 ────────────────────────────────────
echo "[*] Configuring IMDS loopback alias (169.254.169.254)..."
ip addr add "${IMDS_IP}/32" dev lo 2>/dev/null || true

# Persist via systemd service
cat > /etc/systemd/system/pul-imds-ip.service << 'EOF'
[Unit]
Description=PUL Cloud IMDS Loopback Alias (169.254.169.254)
After=network.target
Before=pul-imds.service

[Service]
Type=oneshot
ExecStart=/sbin/ip addr add 169.254.169.254/32 dev lo
ExecStop=/sbin/ip addr del 169.254.169.254/32 dev lo
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable pul-imds-ip --quiet
systemctl start pul-imds-ip 2>/dev/null || true

# ── IMDS Simulator ────────────────────────────────────────────────────────────
echo "[*] Creating IMDS simulator..."
cat > "${IMDS_DIR}/imds.py" << 'PYEOF'
#!/usr/bin/env python3
"""
PUL Cloud Metadata Service — IMDS Simulator
Mimics AWS EC2 Instance Metadata Service at 169.254.169.254
Runs on port 80 (requires root)

Vulnerability: SSRF in the Cloud Developer Portal allows an attacker to
reach this endpoint and steal the IAM role credentials.
"""
from flask import Flask, jsonify, Response
import logging, os

app = Flask(__name__)
LOG_DIR = "/var/log/pul-cloud"
os.makedirs(LOG_DIR, exist_ok=True)
logging.basicConfig(
    filename=f"{LOG_DIR}/imds.log",
    level=logging.WARNING,
    format="%(asctime)s [%(levelname)s] %(message)s"
)

# Simulated IAM credentials — these match MinIO M2 credentials
IAM_CREDS = {
    "Code": "Success",
    "Type": "AWS-HMAC",
    "AccessKeyId": "AKIAPUL2024CLDSVC01",
    "SecretAccessKey": "pULcLd/S3cr3t2024/K3y!",
    "Token": "AQoDYXdzEJr//////////wEaoAK0M2FakeSessionToken4GridfallOp==",
    "Expiration": "2025-12-31T23:59:59Z",
    "LastUpdated": "2024-11-15T06:00:00Z"
}

@app.before_request
def log_request():
    from flask import request
    logging.warning(
        f"IMDS_HIT|src={request.remote_addr}|path={request.path}"
        f"|ua={request.headers.get('User-Agent','unknown')}"
    )

@app.route("/latest/meta-data/")
def metadata_root():
    return Response(
        "ami-id\nami-launch-index\nami-manifest-path\n"
        "hostname\niam/\ninstance-id\ninstance-type\n"
        "local-ipv4\nplacement/\npublic-hostname\npublic-ipv4\n",
        mimetype="text/plain"
    )

@app.route("/latest/meta-data/instance-id")
def instance_id():
    return Response("i-0pul2024cld001a3b7", mimetype="text/plain")

@app.route("/latest/meta-data/instance-type")
def instance_type():
    return Response("pul.cloud.medium", mimetype="text/plain")

@app.route("/latest/meta-data/local-ipv4")
def local_ipv4():
    return Response("11.0.2.10", mimetype="text/plain")

@app.route("/latest/meta-data/hostname")
def hostname():
    return Response("cld-webapp.pul-cloud.internal", mimetype="text/plain")

@app.route("/latest/meta-data/iam/")
def iam_root():
    return Response("info\nsecurity-credentials/\n", mimetype="text/plain")

@app.route("/latest/meta-data/iam/info")
def iam_info():
    return jsonify({
        "Code": "Success",
        "LastUpdated": "2024-11-15T06:00:00Z",
        "InstanceProfileArn": "arn:pul:iam::123456789012:instance-profile/pul-cloud-role",
        "InstanceProfileId": "AIPAJQABLAH4GRIDFALL01"
    })

@app.route("/latest/meta-data/iam/security-credentials/")
def iam_creds_list():
    # Attacker enumerates this first — lists the role name
    return Response("pul-cloud-role\n", mimetype="text/plain")

@app.route("/latest/meta-data/iam/security-credentials/pul-cloud-role")
def iam_creds():
    # THE GOAL — returns cloud IAM credentials
    return jsonify(IAM_CREDS)

@app.route("/latest/meta-data/placement/")
def placement():
    return Response("availability-zone\nregion\n", mimetype="text/plain")

@app.route("/latest/meta-data/placement/region")
def region():
    return Response("in-south-1\n", mimetype="text/plain")

@app.route("/latest/user-data")
def user_data():
    return Response(
        "#!/bin/bash\n# PUL Cloud bootstrap script\n"
        "# cloud-storage-endpoint: http://11.0.2.20:9000\n",
        mimetype="text/plain"
    )

if __name__ == "__main__":
    app.run(host="169.254.169.254", port=80, debug=False)
PYEOF
chmod +x "${IMDS_DIR}/imds.py"

cat > /etc/systemd/system/pul-imds.service << EOF
[Unit]
Description=PUL Cloud Metadata Service (IMDS Simulator)
After=network.target pul-imds-ip.service
Requires=pul-imds-ip.service

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 ${IMDS_DIR}/imds.py
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=pul-imds

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable pul-imds --quiet
systemctl restart pul-imds
sleep 2
echo "[+] IMDS simulator running at http://169.254.169.254"

# ── Cloud Developer Portal (SSRF-vulnerable Flask app) ────────────────────────
echo "[*] Creating PUL Cloud Developer Portal..."
cat > "${APP_DIR}/app.py" << 'PYEOF'
#!/usr/bin/env python3
"""
PUL Cloud Developer Portal
M1 Challenge: SSRF → Cloud Metadata Service → IAM Credential Theft

The 'URL Health Checker' tool fetches arbitrary URLs and displays
the response. An attacker can point it at the Cloud Metadata Service
(169.254.169.254) to steal the instance's IAM role credentials.
"""
from flask import (
    Flask, request, render_template_string, redirect,
    url_for, session, jsonify
)
import hashlib, logging, os, requests as req

app = Flask(__name__)
app.secret_key = "pul-cloud-portal-secret-gridfall-2024"

LOG_DIR = "/var/log/pul-cloud"
os.makedirs(LOG_DIR, exist_ok=True)
logging.basicConfig(
    filename=f"{LOG_DIR}/portal.log",
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s"
)

def h(p): return hashlib.sha256(p.encode()).hexdigest()

USERS = {
    "cloud-dev": {
        "hash": h("CloudDev@PUL2024!"),
        "name": "Cloud Developer",
        "role": "developer"
    },
}
# API key for programmatic access (from AWX job output in Dev Zone M5)
API_KEYS = {
    "pul-cloud-dev-aK8x2mP9!2024": "cloud-dev"
}

BASE = """<!DOCTYPE html><html lang="en">
<head><meta charset="UTF-8"><title>{{ title }} — PUL Cloud Portal</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:-apple-system,'Segoe UI',Arial,sans-serif;background:#0a1628;color:#e2e8f0;min-height:100vh;display:flex;flex-direction:column}
.topbar{background:#051020;border-bottom:2px solid #00d4ff;padding:0 24px;height:56px;display:flex;align-items:center;justify-content:space-between}
.brand{display:flex;align-items:center;gap:10px}
.brand-icon{font-size:22px}
.brand-name{color:#00d4ff;font-size:16px;font-weight:700;letter-spacing:.04em}
.brand-sub{color:rgba(255,255,255,.3);font-size:11px;margin-left:4px}
.topbar-right{color:rgba(255,255,255,.4);font-size:12px;display:flex;align-items:center;gap:16px}
.topbar-right a{color:#00d4ff;text-decoration:none;font-size:12px}
.nav{background:#061222;border-bottom:1px solid rgba(0,212,255,.15);padding:0 24px;display:flex}
.nav a{color:rgba(255,255,255,.45);font-size:13px;padding:10px 16px;text-decoration:none;border-bottom:2px solid transparent;display:block}
.nav a:hover,.nav a.active{color:#00d4ff;border-color:#00d4ff}
.main{flex:1;padding:24px;max-width:1100px;margin:0 auto;width:100%}
.page-title{font-size:20px;font-weight:700;color:#00d4ff;margin-bottom:4px}
.page-sub{font-size:12.5px;color:rgba(255,255,255,.35);margin-bottom:20px}
.card{background:#0d1f38;border:1px solid rgba(0,212,255,.15);border-radius:8px;overflow:hidden;margin-bottom:16px}
.card-header{background:#051020;border-bottom:1px solid rgba(0,212,255,.15);padding:12px 16px;font-size:13px;font-weight:600;color:#00d4ff;display:flex;align-items:center;justify-content:space-between}
.card-body{padding:16px}
.badge{display:inline-block;padding:2px 8px;border-radius:12px;font-size:10px;font-weight:700}
.b-ok{background:rgba(0,184,148,.15);color:#00b894}
.b-warn{background:rgba(253,203,110,.15);color:#fdcb6e}
.b-err{background:rgba(255,107,107,.15);color:#ff6b6b}
.b-info{background:rgba(0,212,255,.15);color:#00d4ff}
.grid3{display:grid;grid-template-columns:repeat(3,1fr);gap:12px}
.stat-card{background:#051020;border:1px solid rgba(0,212,255,.12);border-radius:6px;padding:16px;text-align:center}
.stat-card .n{font-size:28px;font-weight:800;color:#00d4ff}
.stat-card .l{font-size:10.5px;color:rgba(255,255,255,.35);text-transform:uppercase;letter-spacing:.06em;margin-top:3px}
.input{width:100%;padding:9px 12px;background:#051020;border:1.5px solid rgba(0,212,255,.25);border-radius:5px;color:#e2e8f0;font-size:13px;outline:none;font-family:monospace}
.input:focus{border-color:#00d4ff}
.btn{padding:9px 20px;background:#00d4ff;color:#051020;border:none;border-radius:5px;font-size:13px;font-weight:700;cursor:pointer}
.btn-sm{padding:5px 12px;font-size:11.5px}
.btn-outline{background:transparent;border:1.5px solid #00d4ff;color:#00d4ff}
.result-box{background:#020d1a;border:1px solid rgba(0,212,255,.2);border-radius:5px;padding:12px;font-family:monospace;font-size:12px;color:#a8d8ea;white-space:pre-wrap;word-break:break-all;max-height:400px;overflow-y:auto;margin-top:12px}
.form-group{margin-bottom:14px}
.form-group label{display:block;font-size:11px;color:rgba(255,255,255,.5);text-transform:uppercase;letter-spacing:.06em;margin-bottom:5px}
.alert{padding:10px 14px;border-radius:5px;font-size:13px;margin-bottom:14px}
.alert-warn{background:rgba(253,203,110,.08);border:1px solid rgba(253,203,110,.25);color:#fdcb6e}
.alert-info{background:rgba(0,212,255,.06);border:1px solid rgba(0,212,255,.2);color:#74d7f7}
.deploy-row{display:flex;align-items:center;gap:10px;padding:10px 0;border-bottom:1px solid rgba(0,212,255,.08);font-size:12.5px}
.deploy-row:last-child{border-bottom:none}
.footer{background:#051020;border-top:1px solid rgba(0,212,255,.1);padding:8px 24px;text-align:center;font-size:10.5px;color:rgba(255,255,255,.2)}
</style></head>
<body>
<div class="topbar">
  <div class="brand">
    <span class="brand-icon">☁️</span>
    <span class="brand-name">PUL CLOUD PORTAL</span>
    <span class="brand-sub">Developer Console | in-south-1</span>
  </div>
  <div class="topbar-right">
    <span>Instance: cld-webapp.pul-cloud.internal</span>
    {% if session.user %}<span>👤 {{ session.user.name }}</span><a href="/logout">Sign Out</a>{% endif %}
  </div>
</div>
{% if session.user %}
<nav class="nav">
  <a href="/dashboard" {% if active=='dashboard' %}class="active"{% endif %}>Dashboard</a>
  <a href="/deployments" {% if active=='deployments' %}class="active"{% endif %}>Deployments</a>
  <a href="/storage" {% if active=='storage' %}class="active"{% endif %}>Storage</a>
  <a href="/tools" {% if active=='tools' %}class="active"{% endif %}>Tools</a>
  <a href="/settings" {% if active=='settings' %}class="active"{% endif %}>Settings</a>
</nav>
{% endif %}
<div class="main">{% block content %}{% endblock %}</div>
<div class="footer">© 2024 Prabal Urja Limited | PUL Cloud Platform v2.4.1 | Region: in-south-1 | Instance: i-0pul2024cld001a3b7</div>
</body></html>"""

LOGIN_T = BASE.replace("{% block content %}{% endblock %}","""
<div style="display:flex;align-items:center;justify-content:center;min-height:60vh">
<div style="background:#0d1f38;border:1px solid rgba(0,212,255,.2);border-radius:10px;width:400px;overflow:hidden">
  <div style="background:#051020;border-bottom:2px solid #00d4ff;padding:28px;text-align:center">
    <div style="font-size:48px;margin-bottom:8px">☁️</div>
    <div style="font-size:18px;font-weight:700;color:#00d4ff">PUL Cloud Portal</div>
    <div style="font-size:11.5px;color:rgba(255,255,255,.3);margin-top:4px;text-transform:uppercase;letter-spacing:.06em">Developer Sign In</div>
  </div>
  <div style="padding:24px">
    {% if error %}<div class="alert alert-warn">{{ error }}</div>{% endif %}
    <form method="POST">
      <div class="form-group"><label>Username</label><input class="input" name="username" type="text" placeholder="cloud-dev" autocomplete="off"></div>
      <div class="form-group"><label>Password</label><input class="input" name="password" type="password" placeholder="Password"></div>
      <button type="submit" class="btn" style="width:100%">Sign In to Cloud Portal</button>
    </form>
    <div style="text-align:center;font-size:11px;color:rgba(255,255,255,.2);margin-top:14px">PUL Cloud Platform v2.4.1 | in-south-1</div>
  </div>
</div></div>""")

DASH_T = BASE.replace("{% block content %}{% endblock %}","""
<div class="page-title">☁️ Cloud Dashboard</div>
<div class="page-sub">PUL Cloud Platform — Instance Overview | in-south-1</div>
<div class="grid3" style="margin-bottom:16px">
  <div class="stat-card"><div class="n">4</div><div class="l">Running Instances</div></div>
  <div class="stat-card"><div class="n">99.7%</div><div class="l">Uptime (30d)</div></div>
  <div class="stat-card"><div class="n">in-south-1</div><div class="l">Region</div></div>
</div>
<div class="card">
  <div class="card-header">Recent Deployments</div>
  <div class="card-body">
    <div class="deploy-row"><span style="color:#00d4ff;font-family:monospace;font-size:11px">deploy-20241115-047</span><span style="flex:1;margin-left:10px">pul-cloud/platform-svc → 11.0.2.40:5000</span><span class="badge b-ok">SUCCESS</span><span style="color:rgba(255,255,255,.3);font-size:11px;margin-left:10px">2h ago</span></div>
    <div class="deploy-row"><span style="color:#00d4ff;font-family:monospace;font-size:11px">deploy-20241115-046</span><span style="flex:1;margin-left:10px">pul-cloud/iam-service → 11.0.2.50:8080</span><span class="badge b-ok">SUCCESS</span><span style="color:rgba(255,255,255,.3);font-size:11px;margin-left:10px">4h ago</span></div>
    <div class="deploy-row"><span style="color:#00d4ff;font-family:monospace;font-size:11px">deploy-20241114-041</span><span style="flex:1;margin-left:10px">k8s-cluster → 11.0.2.30:6443</span><span class="badge b-warn">PARTIAL</span><span style="color:rgba(255,255,255,.3);font-size:11px;margin-left:10px">18h ago</span></div>
  </div>
</div>
<div class="card">
  <div class="card-header">Cloud Instance Info <span class="badge b-info">i-0pul2024cld001a3b7</span></div>
  <div class="card-body" style="font-family:monospace;font-size:12px;color:rgba(255,255,255,.6);line-height:2">
    <div>Region:         in-south-1</div>
    <div>Instance Type:  pul.cloud.medium</div>
    <div>IAM Role:       pul-cloud-role</div>
    <div>Storage:        s3://pul-cloud-backups (in-south-1)</div>
    <div>K8s Cluster:    11.0.2.30:6443</div>
    <div>Registry:       11.0.2.40:5000</div>
    <div>Metadata URL:   http://169.254.169.254/latest/meta-data/</div>
  </div>
</div>""")

TOOLS_T = BASE.replace("{% block content %}{% endblock %}","""
<div class="page-title">🛠 Developer Tools</div>
<div class="page-sub">Utilities for cloud development and debugging</div>
<div class="alert alert-info">ℹ  The URL Health Checker fetches a URL from this server and returns the raw response. Useful for testing webhooks and internal service connectivity.</div>
<div class="card">
  <div class="card-header">🌐 URL Health Checker</div>
  <div class="card-body">
    <form method="POST" action="/tools/url-check">
      <div class="form-group">
        <label>Target URL</label>
        <input class="input" name="url" type="text" 
               value="{{ last_url or '' }}"
               placeholder="http://example.com/health">
      </div>
      <div style="display:flex;gap:8px">
        <button type="submit" class="btn">Fetch URL</button>
        <button type="submit" name="url" value="http://169.254.169.254/latest/meta-data/" class="btn btn-outline btn-sm">Test IMDS</button>
      </div>
    </form>
    {% if result is not none %}
    <div class="result-box">{{ result }}</div>
    {% endif %}
  </div>
</div>
<div class="card">
  <div class="card-header">🔑 API Key Info</div>
  <div class="card-body" style="font-family:monospace;font-size:12px;color:rgba(255,255,255,.5);line-height:1.9">
    <div>Your API Key   : pul-cloud-dev-aK8x2mP9!2024</div>
    <div>Role           : developer</div>
    <div>IAM Role       : pul-cloud-role</div>
    <div>Metadata Svc   : http://169.254.169.254</div>
  </div>
</div>""")

def login_required(f):
    from functools import wraps
    @wraps(f)
    def wrapped(*a, **kw):
        # Accept session OR API key header
        api_key = request.headers.get("X-Cloud-API-Key", "")
        if api_key in API_KEYS:
            user = USERS[API_KEYS[api_key]]
            session["user"] = {"username": API_KEYS[api_key],
                               "name": user["name"], "role": user["role"]}
        if "user" not in session:
            return redirect(url_for("login"))
        return f(*a, **kw)
    return wrapped

@app.route("/")
def index():
    return redirect(url_for("dashboard") if "user" in session else url_for("login"))

@app.route("/login", methods=["GET", "POST"])
def login():
    error = None
    if request.method == "POST":
        u = request.form.get("username", "").strip()
        p = request.form.get("password", "")
        user = USERS.get(u)
        if user and user["hash"] == h(p):
            session["user"] = {"username": u, "name": user["name"], "role": user["role"]}
            logging.info(f"LOGIN_OK|user={u}|src={request.remote_addr}")
            return redirect(url_for("dashboard"))
        logging.warning(f"LOGIN_FAIL|user={u}|src={request.remote_addr}")
        error = "Invalid credentials."
    return render_template_string(LOGIN_T, title="Sign In", error=error, active="")

@app.route("/logout")
def logout():
    session.clear()
    return redirect(url_for("login"))

@app.route("/dashboard")
@login_required
def dashboard():
    return render_template_string(DASH_T, title="Dashboard", active="dashboard",
                                  session=session)

@app.route("/deployments")
@login_required
def deployments():
    return render_template_string(DASH_T.replace("☁️ Cloud Dashboard","📦 Deployments")
                                  .replace("Instance Overview","Recent deployment history"),
                                  title="Deployments", active="deployments", session=session)

@app.route("/storage")
@login_required
def storage():
    html = DASH_T.replace("☁️ Cloud Dashboard", "🗄 Cloud Storage") \
                 .replace("Instance Overview", "Object storage — in-south-1")
    return render_template_string(html, title="Storage", active="storage", session=session)

@app.route("/settings")
@login_required
def settings():
    html = DASH_T.replace("☁️ Cloud Dashboard","⚙ Settings")
    return render_template_string(html, title="Settings", active="settings", session=session)

@app.route("/tools", methods=["GET"])
@login_required
def tools():
    return render_template_string(TOOLS_T, title="Tools", active="tools",
                                  session=session, result=None, last_url="")

@app.route("/tools/url-check", methods=["POST"])
@login_required
def url_check():
    """
    SSRF VULNERABILITY: fetches an attacker-controlled URL from the server.
    No allowlist/blocklist — any URL including 169.254.169.254 is reachable.
    """
    target_url = request.form.get("url", "").strip()
    result = None
    logging.warning(
        f"URL_CHECK|src={request.remote_addr}|url={target_url}"
        f"|user={session.get('user',{}).get('username','?')}"
    )
    if target_url:
        try:
            resp = req.get(
                target_url,
                timeout=5,
                allow_redirects=True,
                headers={"User-Agent": "PUL-Cloud-HealthChecker/1.0"}
            )
            try:
                import json as _json
                result = _json.dumps(_json.loads(resp.text), indent=2)
            except Exception:
                result = resp.text[:4096]
        except Exception as e:
            result = f"[Error] {e}"

    return render_template_string(TOOLS_T, title="Tools", active="tools",
                                  session=session, result=result, last_url=target_url)

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080, debug=False)
PYEOF
chmod +x "${APP_DIR}/app.py"

# ── Systemd service: Cloud Developer Portal ───────────────────────────────────
cat > /etc/systemd/system/pul-cloud-portal.service << EOF
[Unit]
Description=PUL Cloud Developer Portal (SSRF Challenge — M1)
After=network.target pul-imds.service

[Service]
Type=simple
User=root
WorkingDirectory=${APP_DIR}
ExecStart=/usr/bin/python3 ${APP_DIR}/app.py
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=pul-cloud-portal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable pul-cloud-portal --quiet
systemctl restart pul-cloud-portal
sleep 3

# ── Firewall ──────────────────────────────────────────────────────────────────
if command -v ufw &>/dev/null; then
    ufw allow 8080/tcp comment "PUL Cloud Portal M1" >/dev/null 2>&1 || true
fi

# ── Verification ──────────────────────────────────────────────────────────────
echo ""
echo "[*] Running verification..."
HOST_IP=$(hostname -I | awk '{print $1}')

if systemctl is-active --quiet pul-cloud-portal; then
    echo "[✓] Cloud Portal: http://${HOST_IP}:${PORTAL_PORT}"
else
    echo "[✗] Cloud Portal service failed" >&2
fi

if systemctl is-active --quiet pul-imds; then
    echo "[✓] IMDS Simulator: http://${IMDS_IP} (via loopback alias)"
else
    echo "[✗] IMDS service failed" >&2
fi

# Test SSRF path works (IMDS reachable from localhost)
IMDS_TEST=$(curl -sf "http://${IMDS_IP}/latest/meta-data/iam/security-credentials/pul-cloud-role" 2>/dev/null || echo "FAIL")
if echo "${IMDS_TEST}" | grep -q "AccessKeyId"; then
    echo "[✓] IMDS returning IAM credentials correctly"
else
    echo "[✗] IMDS not responding correctly — check pul-imds-ip service" >&2
fi

echo ""
echo "============================================================"
echo "  M1 Setup Complete — cld-webapp"
echo "  Portal URL   : http://${HOST_IP}:${PORTAL_PORT}"
echo "  Login        : cloud-dev / CloudDev@PUL2024!"
echo "  API Key      : pul-cloud-dev-aK8x2mP9!2024"
echo ""
echo "  CHALLENGE:"
echo "  1. Login to portal → Tools → URL Health Checker"
echo "  2. Fetch: http://169.254.169.254/latest/meta-data/iam/security-credentials/"
echo "  3. Fetch: http://169.254.169.254/latest/meta-data/iam/security-credentials/pul-cloud-role"
echo "  4. Extract: AccessKeyId + SecretAccessKey"
echo ""
echo "  PIVOT CREDENTIAL:"
echo "  AccessKeyId    : AKIAPUL2024CLDSVC01"
echo "  SecretAccessKey: pULcLd/S3cr3t2024/K3y!"
echo "  → Use against M2 MinIO at 11.0.2.20:9000"
echo "  MITRE: T1552.005 (Cloud Instance Metadata API)"
echo "============================================================"

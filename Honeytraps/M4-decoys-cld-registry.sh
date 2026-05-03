#!/usr/bin/env bash
# =============================================================================
# RNG-CLD-01 | M4-cld-registry | Honeytrap Decoys
# Machine theme: Container Registry / Image Management
#
# Decoys (all unique to M4):
#   1. Port 8888 — Fake Harbor Container Registry UI
#   2. Port 8081 — Fake JFrog Artifactory Package Manager
#   3. Port 7777 — Fake Snyk Vulnerability Scan Results Portal
#   4. Port 5001 — Fake Docker Registry v2 Mirror (secondary registry)
#   5. Port 4848 — Fake Trivy Security Scanner Report UI
#   6. Port 5005 — TCP banner: Registry Replication Daemon
# =============================================================================
set -euo pipefail
if [[ $EUID -ne 0 ]]; then echo "[!] Must be run as root." >&2; exit 1; fi
command -v python3 >/dev/null 2>&1 || { echo "[!] python3 required." >&2; exit 1; }

DECOY_DIR="/opt/pul-decoys/m4"
LOG_DIR="/var/log/pul-decoys/m4"
mkdir -p "${DECOY_DIR}" "${LOG_DIR}"

echo "============================================================"
echo "  RNG-CLD-01 | M4-cld-registry | Honeytrap Decoys"
echo "  Prabal Urja Limited — Operation GRIDFALL"
echo "============================================================"

LOGFILE="${LOG_DIR}/honeytrap_hits.log"

# ── DECOY 1: Fake Harbor Registry UI (port 8888) ─────────────────────────────
cat > "${DECOY_DIR}/harbor.py" << 'PYEOF'
from flask import Flask, request, render_template_string, jsonify
import logging

app = Flask(__name__)
LOG_DIR = "/var/log/pul-decoys/m4"
logging.basicConfig(filename=f"{LOG_DIR}/honeytrap_hits.log", level=logging.WARNING,
    format="%(asctime)s [HONEYTRAP] %(message)s")

PAGE = """<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Harbor — PUL Cloud Registry</title>
<style>*{margin:0;padding:0;box-sizing:border-box}body{font-family:-apple-system,Arial,sans-serif;background:#1a1f35;color:#e2e8f0;display:flex;align-items:center;justify-content:center;min-height:100vh}
.box{background:#212741;border:1px solid #2d3561;border-radius:8px;width:420px;overflow:hidden}
.header{background:#131828;padding:24px;text-align:center;border-bottom:2px solid #4a90d9}
.logo{font-size:42px;margin-bottom:8px}
.title{color:#4a90d9;font-size:20px;font-weight:700}
.sub{color:#4b5568;font-size:11px;margin-top:4px}
.body{padding:24px}
.label{font-size:11px;color:#6b7280;margin-bottom:5px;font-weight:700;text-transform:uppercase;letter-spacing:.06em}
input{width:100%;padding:9px 12px;background:#131828;border:1.5px solid #2d3561;border-radius:4px;color:#e2e8f0;font-size:13px;margin-bottom:14px;display:block;outline:none}
input:focus{border-color:#4a90d9}
.btn{width:100%;padding:10px;background:#4a90d9;color:#fff;border:none;border-radius:4px;font-size:14px;font-weight:700;cursor:pointer}
.alert{background:rgba(74,144,217,.08);border:1px solid rgba(74,144,217,.2);border-radius:4px;padding:8px 12px;font-size:12px;color:#7db8eb;margin-bottom:14px}
.oidc{width:100%;margin-top:12px;padding:9px;background:transparent;border:1.5px solid #4a90d9;color:#4a90d9;border-radius:4px;font-size:13px;font-weight:700;cursor:pointer}
</style></head><body>
<div class="box">
  <div class="header"><div class="logo">⚓</div><div class="title">Harbor</div><div class="sub">PUL Container Registry — pul-cloud/platform-svc</div></div>
  <div class="body">
    {% if error %}<div class="alert">{{ error }}</div>{% endif %}
    <form method="POST">
      <div class="label">Username</div><input name="username" placeholder="admin or registry-admin">
      <div class="label">Password</div><input name="password" type="password" placeholder="Harbor password">
      <button type="submit" class="btn">LOG IN</button>
    </form>
    <button class="oidc" onclick="window.location='/c/oidc/login'">LOGIN WITH OIDC PROVIDER</button>
  </div>
</div></body></html>"""

@app.route("/", methods=["GET", "POST"])
@app.route("/harbor/sign-in", methods=["GET", "POST"])
def login():
    error = None
    if request.method == "POST":
        logging.warning(f"HONEYTRAP_HIT|service=harbor-login|src={request.remote_addr}|user={request.form.get('username','')}|pass={request.form.get('password','')}")
        error = "Invalid credentials."
    return render_template_string(PAGE, error=error)

@app.route("/api/v2.0/projects")
def projects():
    auth = request.headers.get("Authorization", "")
    logging.warning(f"HONEYTRAP_HIT|service=harbor-api-projects|src={request.remote_addr}|auth={auth[:60]}")
    return jsonify([{"name": "pul-cloud", "repo_count": 3, "public": False}])

@app.route("/api/v2.0/repositories")
def repos():
    logging.warning(f"HONEYTRAP_HIT|service=harbor-api-repos|src={request.remote_addr}|CRITICAL=REPO_ENUM")
    return jsonify([])

@app.route("/c/oidc/login")
def oidc():
    logging.warning(f"HONEYTRAP_HIT|service=harbor-oidc|src={request.remote_addr}")
    return render_template_string(PAGE.replace("Invalid credentials.", "OIDC provider not available."), error="OIDC provider temporarily unavailable.")

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8888, debug=False)
PYEOF

# ── DECOY 2: Fake JFrog Artifactory (port 8081) ───────────────────────────────
cat > "${DECOY_DIR}/artifactory.py" << 'PYEOF'
from flask import Flask, request, render_template_string, jsonify
import logging

app = Flask(__name__)
LOG_DIR = "/var/log/pul-decoys/m4"
logging.basicConfig(filename=f"{LOG_DIR}/honeytrap_hits.log", level=logging.WARNING,
    format="%(asctime)s [HONEYTRAP] %(message)s")

PAGE = """<!DOCTYPE html><html><head><meta charset="UTF-8"><title>JFrog Artifactory — PUL Cloud</title>
<style>*{margin:0;padding:0;box-sizing:border-box}body{font-family:-apple-system,Arial,sans-serif;background:#1b2032;color:#c8cfd8;display:flex;align-items:center;justify-content:center;min-height:100vh}
.box{background:#242b3d;border:1px solid #2f3b55;border-radius:8px;width:400px;overflow:hidden}
.header{background:#1a2030;padding:24px;text-align:center;border-bottom:2px solid #40c4a0}
.logo{font-size:40px;margin-bottom:8px}
.title{color:#40c4a0;font-size:20px;font-weight:700}
.sub{color:#4b5a6e;font-size:11.5px;margin-top:4px}
.body{padding:24px}
.label{font-size:11px;color:#6b7a8e;margin-bottom:5px;font-weight:700;text-transform:uppercase;letter-spacing:.06em}
input{width:100%;padding:9px 12px;background:#1a2030;border:1.5px solid #2f3b55;border-radius:4px;color:#c8cfd8;font-size:13px;margin-bottom:14px;display:block;outline:none}
.btn{width:100%;padding:10px;background:#40c4a0;color:#fff;border:none;border-radius:4px;font-size:14px;font-weight:700;cursor:pointer}
.sso{width:100%;margin-top:10px;padding:9px;background:transparent;border:1.5px solid #40c4a0;color:#40c4a0;border-radius:4px;font-size:13px;cursor:pointer;font-weight:700}
.footer{font-size:10.5px;color:#4b5a6e;text-align:center;margin-top:14px}
.alert{background:rgba(64,196,160,.08);border:1px solid rgba(64,196,160,.2);border-radius:4px;padding:8px;font-size:12px;color:#6ddbbe;margin-bottom:14px}
</style></head><body>
<div class="box">
  <div class="header"><div class="logo">🐸</div><div class="title">JFrog Artifactory</div><div class="sub">PUL Artifact Repository Manager — OSS Edition</div></div>
  <div class="body">
    {% if error %}<div class="alert">{{ error }}</div>{% endif %}
    <form method="POST">
      <div class="label">Username</div><input name="username" placeholder="admin">
      <div class="label">Password</div><input name="password" type="password" placeholder="Password">
      <button class="btn" type="submit">Login</button>
    </form>
    <button class="sso">Login with SSO</button>
    <div class="footer">JFrog Artifactory v7.71.5 | pul-cloud artifacts</div>
  </div>
</div></body></html>"""

@app.route("/ui/login", methods=["GET", "POST"])
@app.route("/", methods=["GET", "POST"])
def login():
    error = None
    if request.method == "POST":
        logging.warning(f"HONEYTRAP_HIT|service=artifactory-login|src={request.remote_addr}|user={request.form.get('username','')}|pass={request.form.get('password','')}")
        error = "Wrong username or password. Check your credentials and try again."
    return render_template_string(PAGE, error=error)

@app.route("/artifactory/api/system/ping")
def ping():
    return "OK", 200

@app.route("/artifactory/api/repositories")
def repos():
    auth = request.headers.get("Authorization", "")
    logging.warning(f"HONEYTRAP_HIT|service=artifactory-repos|src={request.remote_addr}|auth={auth[:60]}")
    return jsonify([{"key": "pul-docker-local", "type": "LOCAL", "description": "PUL Docker images"}])

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8081, debug=False)
PYEOF

# ── DECOY 3: Fake Snyk Scan Results Portal (port 7777) ────────────────────────
cat > "${DECOY_DIR}/snyk_results.py" << 'PYEOF'
from flask import Flask, request, render_template_string, jsonify
import logging

app = Flask(__name__)
LOG_DIR = "/var/log/pul-decoys/m4"
logging.basicConfig(filename=f"{LOG_DIR}/honeytrap_hits.log", level=logging.WARNING,
    format="%(asctime)s [HONEYTRAP] %(message)s")

@app.before_request
def log_it():
    if request.path not in ("/favicon.ico",):
        logging.warning(f"HONEYTRAP_HIT|service=snyk-portal|src={request.remote_addr}|path={request.path}")

PAGE = """<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Snyk — PUL Container Security</title>
<style>body{font-family:-apple-system,Arial,sans-serif;background:#0e0f17;color:#e2e8f0;min-height:100vh}
.top{background:#05060c;border-bottom:1px solid #2d1f5e;padding:12px 24px;display:flex;align-items:center;gap:10px}
.brand{color:#7c3aed;font-weight:700;font-size:15px}
.main{padding:24px;max-width:900px;margin:0 auto}
.summary{display:grid;grid-template-columns:repeat(4,1fr);gap:12px;margin-bottom:20px}
.scard{background:#141520;border:1px solid #2d1f5e;border-radius:6px;padding:14px;text-align:center}
.scard .n{font-size:28px;font-weight:800}.scard .l{font-size:10.5px;text-transform:uppercase;letter-spacing:.06em;margin-top:3px;color:#6b7280}
.crit-n{color:#ef4444}.high-n{color:#f97316}.med-n{color:#eab308}.low-n{color:#22c55e}
.vuln-card{background:#141520;border:1px solid #2d1f5e;border-radius:6px;padding:14px;margin-bottom:8px}
.vuln-header{display:flex;align-items:center;gap:10px;margin-bottom:6px}
.sev-badge{padding:2px 8px;border-radius:3px;font-size:10px;font-weight:700}
.cr{background:rgba(239,68,68,.15);color:#ef4444}.hi{background:rgba(249,115,22,.15);color:#f97316}
.med-b{background:rgba(234,179,8,.15);color:#eab308}
.vuln-pkg{font-family:monospace;font-size:12px;color:#a78bfa}
.vuln-desc{font-size:12px;color:#6b7280;margin-top:4px}
.login{background:#141520;border:1px solid #2d1f5e;border-radius:8px;padding:28px;max-width:360px;margin:80px auto;text-align:center}
.login input{width:100%;padding:8px 12px;background:#05060c;border:1px solid #2d1f5e;border-radius:4px;color:#e2e8f0;font-size:13px;margin-bottom:12px;display:block}
.login button{width:100%;padding:9px;background:#7c3aed;color:#fff;border:none;border-radius:4px;font-weight:700;cursor:pointer}
</style></head><body>
<div class="top"><span class="brand">🐍 Snyk Container Security</span><span style="color:#6b7280;font-size:12px">Image: pul-cloud/platform-svc:latest</span></div>
<div class="main">
{% if not authed %}
<div class="login"><div style="font-size:40px;margin-bottom:8px">🐍</div>
<div style="font-size:16px;font-weight:700;color:#7c3aed;margin-bottom:16px">Snyk Security Portal</div>
<form method="POST">
  <input name="username" placeholder="Snyk org admin email">
  <input name="password" type="password" placeholder="Password">
  <button type="submit">Sign In</button>
</form></div>
{% else %}
<div style="font-size:16px;font-weight:700;color:#7c3aed;margin-bottom:14px">Scan Results — pul-cloud/platform-svc:latest</div>
<div class="summary">
<div class="scard"><div class="n crit-n">2</div><div class="l">Critical</div></div>
<div class="scard"><div class="n high-n">5</div><div class="l">High</div></div>
<div class="scard"><div class="n med-n">8</div><div class="l">Medium</div></div>
<div class="scard"><div class="n low-n">14</div><div class="l">Low</div></div>
</div>
<div class="vuln-card"><div class="vuln-header"><span class="sev-badge cr">CRITICAL</span><span style="font-size:13px;font-weight:600">Hardcoded credentials detected in image ENV</span></div><div class="vuln-pkg">Layer: /bin/sh -c ENV CLOUD_IAM_USER CLOUD_IAM_PASS</div><div class="vuln-desc">Sensitive environment variables with credential-like names found in image configuration. CWE-798.</div></div>
<div class="vuln-card"><div class="vuln-header"><span class="sev-badge cr">CRITICAL</span><span style="font-size:13px;font-weight:600">CVE-2024-45490 — libexpat heap buffer overflow</span></div><div class="vuln-pkg">libexpat 2.5.0 → fix: 2.6.3</div><div class="vuln-desc">Remote code execution via malformed XML input in libexpat library.</div></div>
<div class="vuln-card"><div class="vuln-header"><span class="sev-badge hi">HIGH</span><span style="font-size:13px;font-weight:600">CVE-2024-3094 — XZ Utils backdoor</span></div><div class="vuln-pkg">xz-utils 5.6.0 → fix: 5.4.6</div><div class="vuln-desc">Supply chain backdoor in XZ Utils liblzma. Malicious code injected in release tarball.</div></div>
{% endif %}
</div></body></html>"""

@app.route("/", methods=["GET", "POST"])
def index():
    authed = False
    if request.method == "POST":
        logging.warning(f"HONEYTRAP_HIT|service=snyk-login|src={request.remote_addr}|user={request.form.get('username','')}|pass={request.form.get('password','')}")
        authed = True
    return render_template_string(PAGE, authed=authed)

@app.route("/api/v1/test/docker/<path:image>")
def test_image(image):
    logging.warning(f"HONEYTRAP_HIT|service=snyk-api-test|src={request.remote_addr}|image={image}|CRITICAL=IMAGE_SCAN_API")
    return jsonify({"ok": False, "issues": {"vulnerabilities": [{"id": "SNYK-001", "severity": "critical"}]}})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=7777, debug=False)
PYEOF

# ── DECOY 4: Fake Docker Registry Mirror (port 5001) ─────────────────────────
cat > "${DECOY_DIR}/registry_mirror.py" << 'PYEOF'
from flask import Flask, request, jsonify, Response
import logging

app = Flask(__name__)
LOG_DIR = "/var/log/pul-decoys/m4"
logging.basicConfig(filename=f"{LOG_DIR}/honeytrap_hits.log", level=logging.WARNING,
    format="%(asctime)s [HONEYTRAP] %(message)s")

@app.before_request
def log_it():
    auth = request.headers.get("Authorization", "none")
    logging.warning(f"HONEYTRAP_HIT|service=registry-mirror|src={request.remote_addr}|method={request.method}|path={request.path}|auth={auth[:60]}")

@app.route("/v2/")
def v2_check():
    return Response("{}", status=200, mimetype="application/json",
                    headers={"Docker-Distribution-Api-Version": "registry/2.0"})

@app.route("/v2/_catalog")
def catalog():
    logging.warning(f"HONEYTRAP_HIT|service=registry-mirror-catalog|src={request.remote_addr}|CRITICAL=REGISTRY_ENUM")
    return jsonify({"repositories": ["pul-cloud/platform-svc", "pul-cloud/iam-service", "library/ubuntu"]})

@app.route("/v2/<path:repo>/manifests/<ref>")
def manifest(repo, ref):
    logging.warning(f"HONEYTRAP_HIT|service=registry-mirror-manifest|src={request.remote_addr}|repo={repo}|ref={ref}|CRITICAL=IMAGE_PULL")
    return Response('{"errors":[{"code":"MANIFEST_UNKNOWN","message":"manifest unknown"}]}',
                    status=404, mimetype="application/json")

@app.route("/v2/<path:repo>/tags/list")
def tags(repo):
    return jsonify({"name": repo, "tags": ["latest", "2.4.0", "2.4.1"]})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5001, debug=False)
PYEOF

# ── DECOY 5: Fake Trivy Scan Report UI (port 4848) ────────────────────────────
cat > "${DECOY_DIR}/trivy_report.py" << 'PYEOF'
from flask import Flask, request, render_template_string, jsonify
import logging

app = Flask(__name__)
LOG_DIR = "/var/log/pul-decoys/m4"
logging.basicConfig(filename=f"{LOG_DIR}/honeytrap_hits.log", level=logging.WARNING,
    format="%(asctime)s [HONEYTRAP] %(message)s")

@app.before_request
def log_it():
    if request.path not in ("/favicon.ico",):
        logging.warning(f"HONEYTRAP_HIT|service=trivy-report|src={request.remote_addr}|path={request.path}")

PAGE = """<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Trivy — Container Scan Reports</title>
<style>body{font-family:-apple-system,Arial,sans-serif;background:#060b14;color:#e2e8f0;min-height:100vh}
.top{background:#020710;border-bottom:1px solid #0f4c8a;padding:12px 24px;display:flex;align-items:center;gap:10px}
.brand{color:#1d8cf8;font-weight:700;font-size:15px}
.main{padding:24px;max-width:960px;margin:0 auto}
.scan-card{background:#0a1525;border:1px solid #0f4c8a;border-radius:6px;padding:16px;margin-bottom:12px}
.scan-head{display:flex;align-items:center;gap:12px;margin-bottom:12px}
.scan-name{font-family:monospace;font-size:14px;font-weight:700;color:#1d8cf8}
.scan-meta{font-size:11px;color:#4b6584;margin-top:2px}
.findings{display:flex;gap:8px;flex-wrap:wrap}
.fc{padding:3px 10px;border-radius:10px;font-size:11px;font-weight:700}
.cr{background:rgba(239,68,68,.15);color:#ef4444}
.hi{background:rgba(249,115,22,.15);color:#f97316}
.me{background:rgba(234,179,8,.15);color:#eab308}
.lo{background:rgba(34,197,94,.15);color:#22c55e}
.secret-alert{background:rgba(239,68,68,.08);border:1px solid rgba(239,68,68,.25);border-radius:4px;padding:10px 14px;margin-top:10px;font-size:12.5px;color:#fca5a5}
.login{background:#0a1525;border:1px solid #0f4c8a;border-radius:8px;padding:28px;max-width:360px;margin:80px auto;text-align:center}
.login input{width:100%;padding:8px 12px;background:#020710;border:1px solid #0f4c8a;border-radius:4px;color:#e2e8f0;font-size:13px;margin-bottom:12px;display:block}
.login button{width:100%;padding:9px;background:#1d8cf8;color:#fff;border:none;border-radius:4px;font-weight:700;cursor:pointer}
</style></head><body>
<div class="top"><span class="brand">🔬 Trivy Security Scanner</span><span style="color:#4b6584;font-size:12px">PUL Cloud Container Security Reports</span></div>
<div class="main">
{% if not authed %}
<div class="login"><div style="font-size:40px;margin-bottom:8px">🔬</div>
<div style="font-size:16px;font-weight:700;color:#1d8cf8;margin-bottom:16px">Trivy Report Portal</div>
<form method="POST">
  <input name="username" placeholder="Username">
  <input name="password" type="password" placeholder="Password">
  <button type="submit">Sign In</button>
</form></div>
{% else %}
<div style="font-size:16px;font-weight:700;color:#1d8cf8;margin-bottom:14px">Recent Scan Reports</div>
<div class="scan-card">
  <div class="scan-head"><div><div class="scan-name">11.0.2.40:5000/pul-cloud/platform-svc:latest</div><div class="scan-meta">Scanned: 2024-11-15 09:30 UTC | Trivy v0.48.3</div></div></div>
  <div class="findings"><span class="fc cr">2 Critical</span><span class="fc hi">5 High</span><span class="fc me">8 Medium</span><span class="fc lo">14 Low</span></div>
  <div class="secret-alert">⚠ SECRET DETECTED — Environment variable CLOUD_IAM_PASS matches credential pattern in image config layer. Recommend immediate rotation.</div>
</div>
<div class="scan-card">
  <div class="scan-head"><div><div class="scan-name">11.0.2.40:5000/pul-cloud/iam-service:3.1.0</div><div class="scan-meta">Scanned: 2024-11-14 22:00 UTC | Trivy v0.48.3</div></div></div>
  <div class="findings"><span class="fc cr">0 Critical</span><span class="fc hi">2 High</span><span class="fc me">11 Medium</span><span class="fc lo">21 Low</span></div>
</div>
{% endif %}
</div></body></html>"""

@app.route("/", methods=["GET", "POST"])
def index():
    authed = False
    if request.method == "POST":
        logging.warning(f"HONEYTRAP_HIT|service=trivy-login|src={request.remote_addr}|user={request.form.get('username','')}|pass={request.form.get('password','')}")
        authed = True
    return render_template_string(PAGE, authed=authed)

@app.route("/api/v1/reports")
def reports():
    return jsonify([{"image": "pul-cloud/platform-svc:latest", "critical": 2, "high": 5}])

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=4848, debug=False)
PYEOF

# ── DECOY 6: TCP Banner — Registry Replication Daemon (port 5005) ─────────────
cat > "${DECOY_DIR}/registry_replication_tcp.py" << 'PYEOF'
import socket, threading, logging, os

LOG_DIR = "/var/log/pul-decoys/m4"
os.makedirs(LOG_DIR, exist_ok=True)
logging.basicConfig(filename=f"{LOG_DIR}/honeytrap_hits.log", level=logging.WARNING,
    format="%(asctime)s [HONEYTRAP] %(message)s")

BANNER = (b"HTTP/1.1 401 Unauthorized\r\n"
          b"WWW-Authenticate: Basic realm=\"PUL Registry Replication\"\r\n"
          b"X-Registry-Node: cld-registry-primary\r\n"
          b"X-Replication-Peer: 11.0.2.41:5005\r\n"
          b"Content-Type: application/json\r\n\r\n"
          b'{"error":"authentication required","realm":"pul-cloud-registry-replication"}\n')

def handle(conn, addr):
    logging.warning(f"HONEYTRAP_HIT|service=registry-replication-tcp|src={addr[0]}:{addr[1]}|proto=TCP|CRITICAL=REPLICATION_PROBE")
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
    s.bind(("0.0.0.0", 5005))
    s.listen(10)
    while True:
        conn, addr = s.accept()
        threading.Thread(target=handle, args=(conn, addr), daemon=True).start()

if __name__ == "__main__":
    serve()
PYEOF

# ── Systemd services ──────────────────────────────────────────────────────────
declare -A SERVICES=(
    ["pul-decoy-m4-harbor"]="${DECOY_DIR}/harbor.py"
    ["pul-decoy-m4-artifactory"]="${DECOY_DIR}/artifactory.py"
    ["pul-decoy-m4-snyk"]="${DECOY_DIR}/snyk_results.py"
    ["pul-decoy-m4-registry-mirror"]="${DECOY_DIR}/registry_mirror.py"
    ["pul-decoy-m4-trivy"]="${DECOY_DIR}/trivy_report.py"
    ["pul-decoy-m4-replication-tcp"]="${DECOY_DIR}/registry_replication_tcp.py"
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
    for PORT in 8888 8081 7777 5001 4848 5005; do
        ufw allow "${PORT}/tcp" comment "Honeytrap M4" >/dev/null 2>&1 || true
    done
fi

echo "============================================================"
echo "  M4 Honeytrap Decoys Active"
echo "  8888 — Fake Harbor Container Registry UI"
echo "  8081 — Fake JFrog Artifactory"
echo "  7777 — Fake Snyk Scan Results Portal"
echo "  5001 — Fake Docker Registry v2 Mirror"
echo "  4848 — Fake Trivy Report UI"
echo "  5005 — TCP Registry Replication Banner"
echo "  Logs → ${LOGFILE}"
echo "============================================================"

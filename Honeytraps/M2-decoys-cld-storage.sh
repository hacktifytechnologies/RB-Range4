#!/usr/bin/env bash
# =============================================================================
# RNG-CLD-01 | M2-cld-storage | Honeytrap Decoys
# Machine theme: Object Storage / S3-compatible
#
# Decoys (all unique to M2):
#   1. Port 10000 — Fake "Azure Blob Storage" REST API endpoint
#   2. Port 4080  — Fake "Backup Manager" web console
#   3. Port 6080  — Fake "DLP (Data Loss Prevention) Scanner" portal
#   4. Port 7070  — Fake "Rclone Web UI" remote storage manager
#   5. Port 5555  — Fake "Restic REST Server" backup endpoint
#   6. Port 9444  — TCP banner: Storage Replication Sync daemon
# =============================================================================
set -euo pipefail
if [[ $EUID -ne 0 ]]; then echo "[!] Must be run as root." >&2; exit 1; fi
command -v python3 >/dev/null 2>&1 || { echo "[!] python3 required." >&2; exit 1; }

DECOY_DIR="/opt/pul-decoys/m2"
LOG_DIR="/var/log/pul-decoys/m2"
mkdir -p "${DECOY_DIR}" "${LOG_DIR}"

echo "============================================================"
echo "  RNG-CLD-01 | M2-cld-storage | Honeytrap Decoys"
echo "  Prabal Urja Limited — Operation GRIDFALL"
echo "============================================================"

LOGFILE="${LOG_DIR}/honeytrap_hits.log"

# ── DECOY 1: Fake Azure Blob Storage REST API (port 10000) ───────────────────
cat > "${DECOY_DIR}/azure_blob.py" << 'PYEOF'
from flask import Flask, request, jsonify, Response
import logging, datetime

app = Flask(__name__)
LOG_DIR = "/var/log/pul-decoys/m2"
logging.basicConfig(filename=f"{LOG_DIR}/honeytrap_hits.log", level=logging.WARNING,
    format="%(asctime)s [HONEYTRAP] %(message)s")

@app.before_request
def log_it():
    logging.warning(f"HONEYTRAP_HIT|service=azure-blob|src={request.remote_addr}|method={request.method}|path={request.path}|auth={request.headers.get('Authorization','none')[:60]}")

@app.route("/<account>", methods=["GET"])
def account_info(account):
    return Response(f"""<?xml version="1.0" encoding="utf-8"?>
<StorageServiceProperties><Logging><Version>1.0</Version></Logging>
<HourMetrics><Enabled>true</Enabled></HourMetrics>
<MinuteMetrics><Enabled>false</Enabled></MinuteMetrics>
</StorageServiceProperties>""", mimetype="application/xml")

@app.route("/<account>/<container>", methods=["GET"])
def list_blobs(account, container):
    return Response(f"""<?xml version="1.0" encoding="utf-8"?>
<EnumerationResults ContainerName="https://pulcloudsa.blob.core.windows.net/{container}">
  <Blobs>
    <Blob><Name>backup-2024-11-14.tar.gz.enc</Name><Properties><Content-Length>145230122</Content-Length><BlobType>BlockBlob</BlobType></Properties></Blob>
    <Blob><Name>config-export-2024-11.json.enc</Name><Properties><Content-Length>8204</Content-Length><BlobType>BlockBlob</BlobType></Properties></Blob>
    <Blob><Name>infra-state.tfstate.enc</Name><Properties><Content-Length>42018</Content-Length><BlobType>BlockBlob</BlobType></Properties></Blob>
  </Blobs>
</EnumerationResults>""", mimetype="application/xml")

@app.route("/<account>/<container>/<path:blob>", methods=["GET"])
def get_blob(account, container, blob):
    logging.warning(f"HONEYTRAP_HIT|service=azure-blob-download|src={request.remote_addr}|blob={container}/{blob}|CRITICAL=BLOB_ACCESS")
    return jsonify({"error": {"code": "BlobAccessTierNotSupported", "message": "This operation is not permitted on this blob."}}), 409

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=10000, debug=False)
PYEOF

# ── DECOY 2: Fake Backup Manager Console (port 4080) ─────────────────────────
cat > "${DECOY_DIR}/backup_manager.py" << 'PYEOF'
from flask import Flask, request, render_template_string
import logging

app = Flask(__name__)
LOG_DIR = "/var/log/pul-decoys/m2"
logging.basicConfig(filename=f"{LOG_DIR}/honeytrap_hits.log", level=logging.WARNING,
    format="%(asctime)s [HONEYTRAP] %(message)s")

PAGE = """<!DOCTYPE html><html><head><meta charset="UTF-8"><title>PUL Backup Manager</title>
<style>*{margin:0;padding:0;box-sizing:border-box}body{font-family:-apple-system,Arial,sans-serif;background:#1a2332;color:#e2e8f0;min-height:100vh}
.top{background:#111b27;border-bottom:1px solid #2d4a6e;padding:12px 24px;display:flex;align-items:center;gap:10px}
.brand{color:#38bdf8;font-weight:700;font-size:15px}
.main{padding:24px;max-width:900px;margin:0 auto}
.card{background:#1e2d3d;border:1px solid #2d4a6e;border-radius:6px;overflow:hidden;margin-bottom:14px}
.card-head{background:#111b27;padding:11px 16px;font-size:13px;font-weight:600;color:#38bdf8;border-bottom:1px solid #2d4a6e}
.card-body{padding:16px}
.table{width:100%;border-collapse:collapse;font-size:12.5px}
.table th{text-align:left;padding:7px 12px;background:#111b27;color:#38bdf8;font-size:10.5px;text-transform:uppercase;border-bottom:1px solid #2d4a6e}
.table td{padding:7px 12px;border-bottom:1px solid #1a2d42}
.badge{display:inline-block;padding:1px 7px;border-radius:10px;font-size:10px;font-weight:700}
.ok{background:rgba(56,189,248,.15);color:#38bdf8}.warn{background:rgba(250,204,21,.15);color:#facc15}
.err{background:rgba(248,113,113,.15);color:#f87171}
.login{background:#1e2d3d;border:1px solid #2d4a6e;border-radius:8px;padding:28px;max-width:360px;margin:80px auto;text-align:center}
.login h2{color:#38bdf8;margin-bottom:16px;font-size:18px}
.login input{width:100%;padding:8px 12px;background:#111b27;border:1px solid #2d4a6e;border-radius:4px;color:#e2e8f0;font-size:13px;margin-bottom:12px;display:block}
.login button{width:100%;padding:9px;background:#38bdf8;color:#000;border:none;border-radius:4px;font-weight:700;cursor:pointer}
</style></head><body>
<div class="top"><span class="brand">🗄 PUL Backup Manager</span><span style="color:#64748b;font-size:12px">Storage: pul-cloud-backups</span></div>
<div class="main">
{% if not authed %}
<div class="login">
  <div style="font-size:40px;margin-bottom:8px">🗄</div>
  <h2>Backup Manager Login</h2>
  <form method="POST">
    <input name="username" placeholder="Username (e.g. backup-admin)">
    <input name="password" type="password" placeholder="Password">
    <button type="submit">Sign In</button>
  </form>
</div>
{% else %}
<div style="font-size:18px;font-weight:700;color:#38bdf8;margin-bottom:16px">📊 Backup Status Overview</div>
<div class="card"><div class="card-head">Recent Backup Jobs</div><div class="card-body" style="padding:0">
<table class="table"><thead><tr><th>Job</th><th>Source</th><th>Destination</th><th>Size</th><th>Status</th><th>Last Run</th></tr></thead>
<tbody>
<tr><td>db-nightly</td><td>203.0.2.15:5432</td><td>s3://pul-cloud-backups/backups/</td><td>2.1 GB</td><td><span class="badge ok">OK</span></td><td>2024-11-15 02:00</td></tr>
<tr><td>config-weekly</td><td>/etc/pul-infra/</td><td>s3://pul-cloud-backups/configs/</td><td>14.2 MB</td><td><span class="badge ok">OK</span></td><td>2024-11-10 03:00</td></tr>
<tr><td>k8s-etcd-snapshot</td><td>11.0.2.30:2379</td><td>s3://pul-cloud-backups/k8s/</td><td>42 MB</td><td><span class="badge warn">WARN: stale</span></td><td>2024-11-15 04:00</td></tr>
<tr><td>vault-backup</td><td>203.0.2.30:8200</td><td>s3://pul-cloud-backups/backups/</td><td>8 MB</td><td><span class="badge ok">OK</span></td><td>2024-11-15 01:00</td></tr>
</tbody></table></div></div>
{% endif %}
</div></body></html>"""

@app.route("/", methods=["GET", "POST"])
def index():
    authed = False
    if request.method == "POST":
        logging.warning(f"HONEYTRAP_HIT|service=backup-manager-login|src={request.remote_addr}|user={request.form.get('username','')}|pass={request.form.get('password','')}")
        authed = True
    return render_template_string(PAGE, authed=authed)

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=4080, debug=False)
PYEOF

# ── DECOY 3: Fake DLP Scanner Portal (port 6080) ─────────────────────────────
cat > "${DECOY_DIR}/dlp_scanner.py" << 'PYEOF'
from flask import Flask, request, render_template_string, jsonify
import logging

app = Flask(__name__)
LOG_DIR = "/var/log/pul-decoys/m2"
logging.basicConfig(filename=f"{LOG_DIR}/honeytrap_hits.log", level=logging.WARNING,
    format="%(asctime)s [HONEYTRAP] %(message)s")

@app.before_request
def log_it():
    if request.path not in ("/favicon.ico",):
        logging.warning(f"HONEYTRAP_HIT|service=dlp-scanner|src={request.remote_addr}|path={request.path}|method={request.method}")

PAGE = """<!DOCTYPE html><html><head><meta charset="UTF-8"><title>PUL DLP Scanner</title>
<style>body{font-family:-apple-system,Arial,sans-serif;background:#0c1f2a;color:#e2e8f0;min-height:100vh}
.top{background:#061420;border-bottom:2px solid #ef4444;padding:12px 24px;display:flex;align-items:center;gap:10px}
.brand{color:#ef4444;font-weight:700;font-size:15px}
.main{padding:24px;max-width:900px;margin:0 auto}
.alert-box{background:rgba(239,68,68,.1);border:1px solid rgba(239,68,68,.3);border-radius:6px;padding:12px 16px;margin-bottom:16px;font-size:13px;color:#fca5a5}
.card{background:#0f2233;border:1px solid #1e3a4f;border-radius:6px;overflow:hidden;margin-bottom:14px}
.card-head{background:#061420;padding:11px 16px;font-size:13px;font-weight:600;color:#ef4444;border-bottom:1px solid #1e3a4f}
.card-body{padding:16px}
.finding{display:flex;align-items:flex-start;gap:12px;padding:10px 0;border-bottom:1px solid #1e3a4f;font-size:12.5px}
.finding:last-child{border-bottom:none}
.sev{min-width:52px;padding:2px 0;text-align:center;border-radius:3px;font-size:10px;font-weight:700}
.crit{background:rgba(239,68,68,.2);color:#ef4444}
.high{background:rgba(249,115,22,.2);color:#fb923c}
.med{background:rgba(234,179,8,.2);color:#fbbf24}
.login{background:#0f2233;border:1px solid #1e3a4f;border-radius:8px;padding:28px;max-width:360px;margin:80px auto;text-align:center}
.login input{width:100%;padding:8px 12px;background:#061420;border:1px solid #1e3a4f;border-radius:4px;color:#e2e8f0;font-size:13px;margin-bottom:12px;display:block}
.login button{width:100%;padding:9px;background:#ef4444;color:#fff;border:none;border-radius:4px;font-weight:700;cursor:pointer}
</style></head><body>
<div class="top"><span class="brand">🔍 PUL Data Loss Prevention Scanner</span></div>
<div class="main">
{% if not authed %}
<div class="login">
  <div style="font-size:40px;margin-bottom:8px">🔍</div>
  <div style="font-size:16px;font-weight:700;color:#ef4444;margin-bottom:16px">DLP Scanner Console</div>
  <form method="POST">
    <input name="username" placeholder="DLP admin username">
    <input name="password" type="password" placeholder="Password">
    <button type="submit">Sign In</button>
  </form>
</div>
{% else %}
<div class="alert-box">⚠ 3 critical findings detected in pul-cloud-backups bucket — immediate review required</div>
<div class="card"><div class="card-head">Latest Scan Findings — s3://pul-cloud-backups (2024-11-15)</div><div class="card-body">
<div class="finding"><span class="sev crit">CRIT</span><div><div style="font-weight:600">Hardcoded credentials found in k8s/cloud-ci-kubeconfig.yaml</div><div style="color:#64748b;margin-top:3px">Bearer token detected: pul-cloud-ci-runner-token-**** [REDACTED]</div></div></div>
<div class="finding"><span class="sev crit">CRIT</span><div><div style="font-weight:600">IAM access key exposed in object metadata</div><div style="color:#64748b;margin-top:3px">Pattern: AKIA*** matches AWS/cloud access key format</div></div></div>
<div class="finding"><span class="sev high">HIGH</span><div><div style="font-weight:600">Bucket pul-cloud-backups has PUBLIC read policy</div><div style="color:#64748b;margin-top:3px">All objects accessible without authentication via S3 API</div></div></div>
<div class="finding"><span class="sev med">MED</span><div><div style="font-weight:600">Encrypted backup file without documented KMS key</div><div style="color:#64748b;margin-top:3px">backups/db-backup-2024-11-14.sql.enc — key provenance unknown</div></div></div>
</div></div>
{% endif %}
</div></body></html>"""

@app.route("/", methods=["GET", "POST"])
def index():
    authed = False
    if request.method == "POST":
        logging.warning(f"HONEYTRAP_HIT|service=dlp-scanner-login|src={request.remote_addr}|user={request.form.get('username','')}|pass={request.form.get('password','')}")
        authed = True
    return render_template_string(PAGE, authed=authed)

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=6080, debug=False)
PYEOF

# ── DECOY 4: Fake Rclone Web UI (port 7070) ───────────────────────────────────
cat > "${DECOY_DIR}/rclone_ui.py" << 'PYEOF'
from flask import Flask, request, render_template_string, jsonify
import logging

app = Flask(__name__)
LOG_DIR = "/var/log/pul-decoys/m2"
logging.basicConfig(filename=f"{LOG_DIR}/honeytrap_hits.log", level=logging.WARNING,
    format="%(asctime)s [HONEYTRAP] %(message)s")

@app.before_request
def log_it():
    if request.path not in ("/favicon.ico",):
        logging.warning(f"HONEYTRAP_HIT|service=rclone-ui|src={request.remote_addr}|path={request.path}|body={request.get_data(as_text=True)[:200]}")

PAGE = """<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Rclone Web UI — PUL Cloud</title>
<style>body{font-family:-apple-system,Arial,sans-serif;background:#181d27;color:#e2e8f0;min-height:100vh}
.top{background:#0f1318;border-bottom:1px solid #2563eb;padding:12px 24px;display:flex;align-items:center;gap:10px}
.brand{color:#60a5fa;font-weight:700;font-size:15px}
.main{padding:24px;max-width:800px;margin:0 auto}
.remote{background:#1e2535;border:1px solid #2d3748;border-radius:6px;padding:14px 18px;margin-bottom:8px;display:flex;align-items:center;gap:12px;cursor:pointer}
.remote:hover{background:#253047;border-color:#2563eb}
.remote-icon{font-size:22px}
.remote-name{font-weight:600;font-size:14px;color:#60a5fa}
.remote-type{font-size:11px;color:#64748b;margin-top:2px}
.remote-path{font-family:monospace;font-size:11px;color:#94a3b8}
.login{background:#1e2535;border:1px solid #2d3748;border-radius:8px;padding:28px;max-width:340px;margin:80px auto;text-align:center}
.login input{width:100%;padding:8px 12px;background:#0f1318;border:1px solid #2d3748;border-radius:4px;color:#e2e8f0;font-size:13px;margin-bottom:12px;display:block}
.login button{width:100%;padding:9px;background:#2563eb;color:#fff;border:none;border-radius:4px;font-weight:700;cursor:pointer}
</style></head><body>
<div class="top"><span class="brand">☁ Rclone Web UI</span><span style="color:#64748b;font-size:12px">v1.65.0 — PUL Cloud Storage Manager</span></div>
<div class="main">
{% if not authed %}
<div class="login">
  <div style="font-size:40px;margin-bottom:8px">☁</div>
  <div style="font-size:16px;font-weight:700;color:#60a5fa;margin-bottom:16px">Rclone Web UI</div>
  <form method="POST">
    <input name="username" placeholder="Username">
    <input name="password" type="password" placeholder="Password">
    <button type="submit">Login</button>
  </form>
</div>
{% else %}
<div style="font-size:18px;font-weight:700;color:#60a5fa;margin-bottom:16px">🗂 Configured Remotes</div>
<div class="remote"><span class="remote-icon">🪣</span><div><div class="remote-name">pul-cloud-s3</div><div class="remote-type">S3 Compatible (MinIO)</div><div class="remote-path">endpoint=http://11.0.2.20:9000 bucket=pul-cloud-backups</div></div></div>
<div class="remote"><span class="remote-icon">🔵</span><div><div class="remote-name">azure-pul-prod</div><div class="remote-type">Azure Blob Storage</div><div class="remote-path">account=pulcloudsa container=pul-backups-prod</div></div></div>
<div class="remote"><span class="remote-icon">🟠</span><div><div class="remote-name">gcs-pul-archive</div><div class="remote-type">Google Cloud Storage</div><div class="remote-path">bucket=pul-cloud-archive-in1 project=pul-cloud-prod</div></div></div>
<div class="remote"><span class="remote-icon">💾</span><div><div class="remote-name">local-backup-mount</div><div class="remote-type">Local Filesystem</div><div class="remote-path">/mnt/backup-share/</div></div></div>
{% endif %}
</div></body></html>"""

@app.route("/", methods=["GET", "POST"])
def index():
    authed = False
    if request.method == "POST":
        logging.warning(f"HONEYTRAP_HIT|service=rclone-login|src={request.remote_addr}|user={request.form.get('username','')}|pass={request.form.get('password','')}")
        authed = True
    return render_template_string(PAGE, authed=authed)

@app.route("/api/rc/noop", methods=["POST"])
def noop():
    return jsonify({}), 200

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=7070, debug=False)
PYEOF

# ── DECOY 5: Fake Restic REST Server (port 5555) ─────────────────────────────
cat > "${DECOY_DIR}/restic_rest.py" << 'PYEOF'
from flask import Flask, request, jsonify, Response
import logging

app = Flask(__name__)
LOG_DIR = "/var/log/pul-decoys/m2"
logging.basicConfig(filename=f"{LOG_DIR}/honeytrap_hits.log", level=logging.WARNING,
    format="%(asctime)s [HONEYTRAP] %(message)s")

@app.before_request
def log_it():
    logging.warning(f"HONEYTRAP_HIT|service=restic-rest|src={request.remote_addr}|method={request.method}|path={request.path}|auth={request.authorization}")

# Restic REST protocol: GET / returns repository list, GET /<repo>/ returns snapshots
@app.route("/")
def index():
    return Response('["pul-infra-backup","pul-db-backup","pul-k8s-backup"]',
                    mimetype="application/vnd.x.restic.rest.v2")

@app.route("/<repo>/")
def repo(repo):
    return Response('{"version":2}', mimetype="application/vnd.x.restic.rest.v2")

@app.route("/<repo>/snapshots")
def snapshots(repo):
    logging.warning(f"HONEYTRAP_HIT|service=restic-rest-snapshots|src={request.remote_addr}|repo={repo}|CRITICAL=SNAPSHOT_ENUM")
    return Response('[]', mimetype="application/vnd.x.restic.rest.v2")

@app.route("/<repo>/<path:key>", methods=["GET", "POST", "DELETE"])
def data(repo, key):
    return Response('{"error":"not found"}', status=404, mimetype="application/vnd.x.restic.rest.v2")

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5555, debug=False)
PYEOF

# ── DECOY 6: TCP Banner — Storage Replication Sync (port 9444) ───────────────
cat > "${DECOY_DIR}/storage_replication_tcp.py" << 'PYEOF'
import socket, threading, logging, os

LOG_DIR = "/var/log/pul-decoys/m2"
os.makedirs(LOG_DIR, exist_ok=True)
logging.basicConfig(filename=f"{LOG_DIR}/honeytrap_hits.log", level=logging.WARNING,
    format="%(asctime)s [HONEYTRAP] %(message)s")

BANNER = b"PUL-STORAGE-SYNC/1.2 READY node=cld-storage.pul-cloud.internal role=primary peer=11.0.2.21:9444\r\n"

def handle(conn, addr):
    logging.warning(f"HONEYTRAP_HIT|service=storage-replication-tcp|src={addr[0]}:{addr[1]}|proto=TCP")
    try:
        conn.sendall(BANNER)
        conn.recv(256)
        conn.sendall(b"ERR AUTH_REQUIRED\r\n")
    except Exception:
        pass
    finally:
        conn.close()

def serve():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("0.0.0.0", 9444))
    s.listen(10)
    while True:
        conn, addr = s.accept()
        threading.Thread(target=handle, args=(conn, addr), daemon=True).start()

if __name__ == "__main__":
    serve()
PYEOF

# ── Systemd services ──────────────────────────────────────────────────────────
declare -A SERVICES=(
    ["pul-decoy-m2-azure-blob"]="${DECOY_DIR}/azure_blob.py"
    ["pul-decoy-m2-backup-manager"]="${DECOY_DIR}/backup_manager.py"
    ["pul-decoy-m2-dlp-scanner"]="${DECOY_DIR}/dlp_scanner.py"
    ["pul-decoy-m2-rclone-ui"]="${DECOY_DIR}/rclone_ui.py"
    ["pul-decoy-m2-restic-rest"]="${DECOY_DIR}/restic_rest.py"
    ["pul-decoy-m2-storage-replication"]="${DECOY_DIR}/storage_replication_tcp.py"
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
    for PORT in 10000 4080 6080 7070 5555 9444; do
        ufw allow "${PORT}/tcp" comment "Honeytrap M2" >/dev/null 2>&1 || true
    done
fi

echo "============================================================"
echo "  M2 Honeytrap Decoys Active"
echo "  10000 — Fake Azure Blob Storage REST API"
echo "  4080  — Fake Backup Manager Console"
echo "  6080  — Fake DLP Scanner Portal"
echo "  7070  — Fake Rclone Web UI"
echo "  5555  — Fake Restic REST Server"
echo "  9444  — TCP Storage Replication Sync Banner"
echo "  Logs → ${LOGFILE}"
echo "============================================================"

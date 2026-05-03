#!/usr/bin/env bash
# =============================================================================
# RNG-CLD-01 | M5-cld-iam | Honeytrap Decoys
# Machine theme: IAM / Identity & Access Management
#
# Decoys (all unique to M5):
#   1. Port 8200 — Fake HashiCorp Vault UI + API
#   2. Port 8180 — Fake Keycloak Identity Provider portal
#   3. Port 4444 — Fake CyberArk PAM portal
#   4. Port 9191 — Fake Teleport Access Proxy (SSH/K8s gateway)
#   5. Port 1812 — TCP banner: RADIUS authentication service
#   6. Port 636  — TCP banner: LDAPS service (AD integration)
# =============================================================================
set -euo pipefail
if [[ $EUID -ne 0 ]]; then echo "[!] Must be run as root." >&2; exit 1; fi
command -v python3 >/dev/null 2>&1 || { echo "[!] python3 required." >&2; exit 1; }

DECOY_DIR="/opt/pul-decoys/m5"
LOG_DIR="/var/log/pul-decoys/m5"
mkdir -p "${DECOY_DIR}" "${LOG_DIR}"

echo "============================================================"
echo "  RNG-CLD-01 | M5-cld-iam | Honeytrap Decoys"
echo "  Prabal Urja Limited — Operation GRIDFALL"
echo "============================================================"

LOGFILE="${LOG_DIR}/honeytrap_hits.log"

# ── DECOY 1: Fake HashiCorp Vault UI + API (port 8200) ───────────────────────
cat > "${DECOY_DIR}/vault_ui.py" << 'PYEOF'
from flask import Flask, request, render_template_string, jsonify
import logging

app = Flask(__name__)
LOG_DIR = "/var/log/pul-decoys/m5"
logging.basicConfig(filename=f"{LOG_DIR}/honeytrap_hits.log", level=logging.WARNING,
    format="%(asctime)s [HONEYTRAP] %(message)s")

PAGE = """<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Vault — PUL Secrets Management</title>
<style>*{margin:0;padding:0;box-sizing:border-box}body{font-family:-apple-system,Arial,sans-serif;background:#1b1b1b;color:#cfd8e3;display:flex;align-items:center;justify-content:center;min-height:100vh}
.box{background:#1f2937;border:1px solid #374151;border-radius:8px;width:400px;overflow:hidden}
.header{background:#111827;padding:24px;text-align:center;border-bottom:2px solid #fbbf24}
.logo{font-size:44px;margin-bottom:8px}
.title{color:#fbbf24;font-size:20px;font-weight:700}
.sub{color:#4b5563;font-size:11.5px;margin-top:4px}
.body{padding:24px}
.tabs{display:flex;margin-bottom:20px;background:#111827;border-radius:4px;overflow:hidden}
.tab{flex:1;padding:8px;text-align:center;font-size:12.5px;cursor:pointer;color:#6b7280}
.tab.active{background:#1f2937;color:#fbbf24;font-weight:700}
.label{font-size:11px;color:#6b7280;margin-bottom:5px;font-weight:700;text-transform:uppercase;letter-spacing:.06em}
input{width:100%;padding:9px 12px;background:#111827;border:1.5px solid #374151;border-radius:4px;color:#cfd8e3;font-size:13px;margin-bottom:14px;display:block;outline:none}
input:focus{border-color:#fbbf24}
.btn{width:100%;padding:10px;background:#fbbf24;color:#111827;border:none;border-radius:4px;font-size:14px;font-weight:700;cursor:pointer}
.note{font-size:11px;color:#4b5563;text-align:center;margin-top:12px}
.alert{background:rgba(251,191,36,.08);border:1px solid rgba(251,191,36,.2);border-radius:4px;padding:8px 12px;font-size:12px;color:#fcd34d;margin-bottom:14px}
</style></head><body>
<div class="box">
  <div class="header"><div class="logo">🔐</div><div class="title">HashiCorp Vault</div><div class="sub">PUL Cloud Secrets Management — in-south-1</div></div>
  <div class="body">
    {% if error %}<div class="alert">{{ error }}</div>{% endif %}
    <div class="tabs"><div class="tab active">Token</div><div class="tab">Username</div><div class="tab">OIDC</div></div>
    <form method="POST">
      <div class="label">Token</div>
      <input name="token" type="password" placeholder="s.XXXXXXXXXXXXXXXX or hvs.XXX">
      <button type="submit" class="btn">Sign In</button>
    </form>
    <div class="note">Vault v1.15.4 | Server: vault.pul-cloud.internal</div>
  </div>
</div></body></html>"""

@app.route("/ui/", methods=["GET", "POST"])
@app.route("/", methods=["GET", "POST"])
def ui():
    error = None
    if request.method == "POST":
        logging.warning(f"HONEYTRAP_HIT|service=vault-ui-login|src={request.remote_addr}|token={request.form.get('token','')}|CRITICAL=VAULT_TOKEN_SUBMIT")
        error = "Invalid Vault token."
    return render_template_string(PAGE, error=error)

@app.route("/v1/auth/token/lookup-self", methods=["GET"])
def lookup_self():
    auth = request.headers.get("X-Vault-Token", "")
    logging.warning(f"HONEYTRAP_HIT|service=vault-api-token-lookup|src={request.remote_addr}|token={auth}|CRITICAL=VAULT_TOKEN_PROBE")
    return jsonify({"errors": ["permission denied"]}), 403

@app.route("/v1/sys/health")
def health():
    return jsonify({"initialized": True, "sealed": False, "standby": False, "version": "1.15.4", "cluster_name": "pul-cloud"})

@app.route("/v1/secret/data/<path:path>")
def secret(path):
    auth = request.headers.get("X-Vault-Token", "")
    logging.warning(f"HONEYTRAP_HIT|service=vault-api-secret|src={request.remote_addr}|path={path}|token={auth}|CRITICAL=SECRET_READ_ATTEMPT")
    return jsonify({"errors": ["1 error occurred: * permission denied"]}), 403

@app.route("/v1/auth/approle/login", methods=["POST"])
def approle_login():
    data = request.get_json(silent=True) or {}
    logging.warning(f"HONEYTRAP_HIT|service=vault-approle-login|src={request.remote_addr}|role_id={data.get('role_id','')}|secret_id={data.get('secret_id','')}|CRITICAL=APPROLE_LOGIN")
    return jsonify({"errors": ["approle login failed — invalid role_id or secret_id"]}), 400

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8200, debug=False)
PYEOF

# ── DECOY 2: Fake Keycloak Identity Provider (port 8180) ──────────────────────
cat > "${DECOY_DIR}/keycloak.py" << 'PYEOF'
from flask import Flask, request, render_template_string, jsonify, redirect
import logging

app = Flask(__name__)
LOG_DIR = "/var/log/pul-decoys/m5"
logging.basicConfig(filename=f"{LOG_DIR}/honeytrap_hits.log", level=logging.WARNING,
    format="%(asctime)s [HONEYTRAP] %(message)s")

PAGE = """<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Keycloak — PUL Cloud IdP</title>
<style>*{margin:0;padding:0;box-sizing:border-box}body{font-family:-apple-system,Arial,sans-serif;background:#1e2033;color:#d4d9e8;display:flex;align-items:center;justify-content:center;min-height:100vh}
.box{background:#252840;border:1px solid #3a3f60;border-radius:8px;width:400px;overflow:hidden}
.header{background:#1a1c30;padding:24px;text-align:center;border-bottom:2px solid #3d5a80}
.logo{font-size:42px;margin-bottom:8px}
.title{color:#6ca0dc;font-size:20px;font-weight:700}
.sub{color:#4a5270;font-size:11.5px;margin-top:4px}
.body{padding:24px}
.realm{background:#1a1c30;border:1px solid #3a3f60;border-radius:4px;padding:8px 12px;font-size:12px;color:#6ca0dc;margin-bottom:16px;text-align:center;font-family:monospace}
.label{font-size:11px;color:#6b7280;margin-bottom:5px;font-weight:700;text-transform:uppercase;letter-spacing:.06em}
input{width:100%;padding:9px 12px;background:#1a1c30;border:1.5px solid #3a3f60;border-radius:4px;color:#d4d9e8;font-size:13px;margin-bottom:14px;display:block;outline:none}
input:focus{border-color:#6ca0dc}
.btn{width:100%;padding:10px;background:#3d5a80;color:#fff;border:none;border-radius:4px;font-size:14px;font-weight:700;cursor:pointer}
.social{margin-top:14px;text-align:center;font-size:12px;color:#4a5270}
.social a{color:#6ca0dc;text-decoration:none}
.alert{background:rgba(108,160,220,.08);border:1px solid rgba(108,160,220,.2);border-radius:4px;padding:8px 12px;font-size:12px;color:#89b8e8;margin-bottom:14px}
</style></head><body>
<div class="box">
  <div class="header"><div class="logo">🗝</div><div class="title">Keycloak</div><div class="sub">PUL Cloud Identity Provider</div></div>
  <div class="body">
    {% if error %}<div class="alert">{{ error }}</div>{% endif %}
    <div class="realm">Realm: pul-cloud-internal</div>
    <form method="POST">
      <div class="label">Username or email</div><input name="username" placeholder="user@prabalurja.in">
      <div class="label">Password</div><input name="password" type="password" placeholder="Password">
      <button class="btn" type="submit">Sign In</button>
    </form>
    <div class="social">Forgot password? <a href="/realms/pul-cloud-internal/login-actions/reset-credentials">Reset credentials</a></div>
  </div>
</div></body></html>"""

@app.route("/", methods=["GET"])
def root():
    return redirect("/realms/pul-cloud-internal/account/")

@app.route("/realms/<realm>/protocol/openid-connect/auth", methods=["GET", "POST"])
@app.route("/realms/<realm>/account/", methods=["GET", "POST"])
def login(realm):
    error = None
    if request.method == "POST":
        logging.warning(f"HONEYTRAP_HIT|service=keycloak-login|src={request.remote_addr}|realm={realm}|user={request.form.get('username','')}|pass={request.form.get('password','')}")
        error = "Invalid username or password."
    return render_template_string(PAGE, error=error)

@app.route("/realms/<realm>/.well-known/openid-configuration")
def oidc_discovery(realm):
    logging.warning(f"HONEYTRAP_HIT|service=keycloak-oidc-discovery|src={request.remote_addr}|realm={realm}")
    base = f"http://11.0.2.50:8180/realms/{realm}"
    return jsonify({"issuer": base, "authorization_endpoint": f"{base}/protocol/openid-connect/auth",
                    "token_endpoint": f"{base}/protocol/openid-connect/token",
                    "userinfo_endpoint": f"{base}/protocol/openid-connect/userinfo"})

@app.route("/realms/<realm>/protocol/openid-connect/token", methods=["POST"])
def token(realm):
    logging.warning(f"HONEYTRAP_HIT|service=keycloak-token-endpoint|src={request.remote_addr}|realm={realm}|data={request.form.to_dict()}|CRITICAL=TOKEN_REQUEST")
    return jsonify({"error": "invalid_client", "error_description": "Invalid client credentials"}), 401

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8180, debug=False)
PYEOF

# ── DECOY 3: Fake CyberArk PAM Portal (port 4444) ────────────────────────────
cat > "${DECOY_DIR}/cyberark.py" << 'PYEOF'
from flask import Flask, request, render_template_string, jsonify
import logging

app = Flask(__name__)
LOG_DIR = "/var/log/pul-decoys/m5"
logging.basicConfig(filename=f"{LOG_DIR}/honeytrap_hits.log", level=logging.WARNING,
    format="%(asctime)s [HONEYTRAP] %(message)s")

PAGE = """<!DOCTYPE html><html><head><meta charset="UTF-8"><title>CyberArk PAS — PUL Cloud</title>
<style>*{margin:0;padding:0;box-sizing:border-box}body{font-family:-apple-system,Arial,sans-serif;background:#0e1420;color:#c8d3de;display:flex;align-items:center;justify-content:center;min-height:100vh}
.box{background:#16202e;border:1px solid #1e3a5f;border-radius:8px;width:420px;overflow:hidden}
.header{background:#0a1220;padding:24px;text-align:center;border-bottom:2px solid #00a3e0}
.logo{font-size:40px;margin-bottom:8px}
.title{color:#00a3e0;font-size:20px;font-weight:700}
.sub{color:#3a5070;font-size:11.5px;margin-top:4px}
.body{padding:24px}
.label{font-size:11px;color:#6b8099;margin-bottom:5px;font-weight:700;text-transform:uppercase;letter-spacing:.06em}
input{width:100%;padding:9px 12px;background:#0a1220;border:1.5px solid #1e3a5f;border-radius:4px;color:#c8d3de;font-size:13px;margin-bottom:14px;display:block;outline:none}
input:focus{border-color:#00a3e0}
.btn{width:100%;padding:10px;background:#00a3e0;color:#fff;border:none;border-radius:4px;font-size:14px;font-weight:700;cursor:pointer}
.mfa{display:flex;gap:8px;margin-bottom:14px}
.mfa input{margin-bottom:0;text-align:center;font-size:18px;font-weight:700;letter-spacing:.1em}
.footer{font-size:10.5px;color:#3a5070;text-align:center;margin-top:14px}
.alert{background:rgba(0,163,224,.08);border:1px solid rgba(0,163,224,.2);border-radius:4px;padding:8px 12px;font-size:12px;color:#5bc8f0;margin-bottom:14px}
</style></head><body>
<div class="box">
  <div class="header"><div class="logo">🛡</div><div class="title">CyberArk PAS</div><div class="sub">Privileged Access Security — PUL Cloud</div></div>
  <div class="body">
    {% if error %}<div class="alert">{{ error }}</div>{% endif %}
    <form method="POST">
      <div class="label">Username</div><input name="username" placeholder="CYBERANGE\\svc_itadmin or UPN">
      <div class="label">Password</div><input name="password" type="password" placeholder="Windows/LDAP password">
      <div class="label">MFA Code (optional)</div>
      <input name="mfa" placeholder="6-digit code">
      <button class="btn" type="submit">Sign In</button>
    </form>
    <div class="footer">CyberArk PAS v14.0 | Vault: pul-cyberark-vault.internal</div>
  </div>
</div></body></html>"""

@app.route("/PasswordVault/", methods=["GET", "POST"])
@app.route("/", methods=["GET", "POST"])
def login():
    error = None
    if request.method == "POST":
        logging.warning(f"HONEYTRAP_HIT|service=cyberark-login|src={request.remote_addr}|user={request.form.get('username','')}|pass={request.form.get('password','')}|mfa={request.form.get('mfa','')}|CRITICAL=PAM_CRED_SUBMIT")
        error = "Authentication failed. Check your credentials."
    return render_template_string(PAGE, error=error)

@app.route("/PasswordVault/API/Auth/LDAP/Logon", methods=["POST"])
def api_logon():
    data = request.get_json(silent=True) or {}
    logging.warning(f"HONEYTRAP_HIT|service=cyberark-api-logon|src={request.remote_addr}|user={data.get('username','')}|pass={data.get('password','')}|CRITICAL=PAM_API_LOGIN")
    return jsonify({"ErrorCode": "ITATS127E", "ErrorMessage": "Authentication failure for user"}), 401

@app.route("/PasswordVault/API/Accounts", methods=["GET"])
def accounts():
    auth = request.headers.get("Authorization", "")
    logging.warning(f"HONEYTRAP_HIT|service=cyberark-api-accounts|src={request.remote_addr}|auth={auth[:60]}|CRITICAL=PAM_ACCOUNT_ENUM")
    return jsonify({"ErrorCode": "PASWS011E", "ErrorMessage": "User is not authorized to perform this action."}), 403

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=4444, debug=False)
PYEOF

# ── DECOY 4: Fake Teleport Access Proxy (port 9191) ──────────────────────────
cat > "${DECOY_DIR}/teleport.py" << 'PYEOF'
from flask import Flask, request, render_template_string, jsonify
import logging

app = Flask(__name__)
LOG_DIR = "/var/log/pul-decoys/m5"
logging.basicConfig(filename=f"{LOG_DIR}/honeytrap_hits.log", level=logging.WARNING,
    format="%(asctime)s [HONEYTRAP] %(message)s")

PAGE = """<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Teleport — PUL Cloud Access</title>
<style>*{margin:0;padding:0;box-sizing:border-box}body{font-family:-apple-system,Arial,sans-serif;background:#0f172a;color:#e2e8f0;display:flex;align-items:center;justify-content:center;min-height:100vh}
.box{background:#1e293b;border:1px solid #334155;border-radius:10px;width:420px;overflow:hidden}
.header{background:#0f172a;padding:24px;text-align:center;border-bottom:2px solid #6366f1}
.logo{font-size:44px;margin-bottom:8px}
.title{color:#818cf8;font-size:20px;font-weight:700}
.sub{color:#475569;font-size:11.5px;margin-top:4px}
.body{padding:24px}
.sso-btn{width:100%;padding:10px;background:#6366f1;color:#fff;border:none;border-radius:6px;font-size:14px;font-weight:700;cursor:pointer;margin-bottom:12px}
.local-btn{width:100%;padding:9px;background:transparent;border:1.5px solid #6366f1;color:#818cf8;border-radius:6px;font-size:13px;font-weight:700;cursor:pointer}
.divider{display:flex;align-items:center;gap:12px;margin:16px 0;font-size:11px;color:#475569}
.divider::before,.divider::after{content:'';flex:1;border-top:1px solid #334155}
.label{font-size:11px;color:#64748b;margin-bottom:5px;font-weight:700;text-transform:uppercase;letter-spacing:.06em}
input{width:100%;padding:9px 12px;background:#0f172a;border:1.5px solid #334155;border-radius:5px;color:#e2e8f0;font-size:13px;margin-bottom:12px;display:block;outline:none}
.submit{width:100%;padding:10px;background:#6366f1;color:#fff;border:none;border-radius:5px;font-size:14px;font-weight:700;cursor:pointer}
.alert{background:rgba(99,102,241,.08);border:1px solid rgba(99,102,241,.2);border-radius:5px;padding:8px 12px;font-size:12px;color:#a5b4fc;margin-bottom:14px}
.footer{font-size:10.5px;color:#334155;text-align:center;margin-top:12px}
</style></head><body>
<div class="box">
  <div class="header"><div class="logo">🌀</div><div class="title">Teleport</div><div class="sub">PUL Cloud Infrastructure Access Platform</div></div>
  <div class="body">
    {% if error %}<div class="alert">{{ error }}</div>{% endif %}
    <button class="sso-btn">Sign In with PUL SSO</button>
    <div class="divider">or sign in with local account</div>
    <form method="POST">
      <div class="label">Username</div><input name="username" placeholder="Local Teleport username">
      <div class="label">Password</div><input name="password" type="password" placeholder="Password">
      <button class="submit" type="submit">Continue</button>
    </form>
    <div class="footer">Teleport v14.3.2 | Cluster: pul-cloud.teleport.internal</div>
  </div>
</div></body></html>"""

@app.route("/web/login", methods=["GET", "POST"])
@app.route("/", methods=["GET", "POST"])
def login():
    error = None
    if request.method == "POST":
        logging.warning(f"HONEYTRAP_HIT|service=teleport-login|src={request.remote_addr}|user={request.form.get('username','')}|pass={request.form.get('password','')}")
        error = "Invalid credentials."
    return render_template_string(PAGE, error=error)

@app.route("/webapi/ping")
def ping():
    return jsonify({"server_version": "14.3.2", "cluster_name": "pul-cloud",
                    "auth": {"type": "saml", "second_factor": "otp"}, "proxy_public_addr": "11.0.2.50:9191"})

@app.route("/webapi/nodes")
def nodes():
    auth = request.headers.get("Authorization", "")
    logging.warning(f"HONEYTRAP_HIT|service=teleport-nodes|src={request.remote_addr}|auth={auth[:60]}|CRITICAL=NODE_ENUM")
    return jsonify({"items": [], "startKey": ""}), 200

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=9191, debug=False)
PYEOF

# ── DECOY 5: TCP Banner — RADIUS auth service (port 1812) ────────────────────
cat > "${DECOY_DIR}/radius_tcp.py" << 'PYEOF'
import socket, threading, logging, os

LOG_DIR = "/var/log/pul-decoys/m5"
os.makedirs(LOG_DIR, exist_ok=True)
logging.basicConfig(filename=f"{LOG_DIR}/honeytrap_hits.log", level=logging.WARNING,
    format="%(asctime)s [HONEYTRAP] %(message)s")

# RADIUS normally runs on UDP/1812 but attackers probe TCP too
# Return a fake banner to identify the service
BANNER = b"PUL-RADIUS/3.0.27 READY realm=pul-cloud.internal backends=cyberange.local,pul-cloud-internal\r\n"

def handle(conn, addr):
    logging.warning(f"HONEYTRAP_HIT|service=radius-tcp|src={addr[0]}:{addr[1]}|proto=TCP|CRITICAL=RADIUS_PROBE")
    try:
        conn.sendall(BANNER)
        conn.recv(256)
        conn.sendall(b"ERR PROTOCOL_MISMATCH RADIUS requires UDP\r\n")
    except Exception:
        pass
    finally:
        conn.close()

def serve():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("0.0.0.0", 1812))
    s.listen(10)
    while True:
        conn, addr = s.accept()
        threading.Thread(target=handle, args=(conn, addr), daemon=True).start()

if __name__ == "__main__":
    serve()
PYEOF

# ── DECOY 6: TCP Banner — LDAPS service (port 636) ───────────────────────────
cat > "${DECOY_DIR}/ldaps_tcp.py" << 'PYEOF'
import socket, threading, logging, os

LOG_DIR = "/var/log/pul-decoys/m5"
os.makedirs(LOG_DIR, exist_ok=True)
logging.basicConfig(filename=f"{LOG_DIR}/honeytrap_hits.log", level=logging.WARNING,
    format="%(asctime)s [HONEYTRAP] %(message)s")

# Minimal LDAP banner — enough to fingerprint as LDAP
# Real LDAPS would do a TLS handshake; we just return a generic error
LDAP_ERR = (
    b"\x30\x0c"           # SEQUENCE
    b"\x02\x01\x01"       # messageID: 1
    b"\x61\x07"           # bindResponse
    b"\x0a\x01\x31"       # resultCode: 49 (invalidCredentials)
    b"\x04\x00"           # matchedDN: empty
    b"\x04\x00"           # diagnosticMessage: empty
)

def handle(conn, addr):
    logging.warning(f"HONEYTRAP_HIT|service=ldaps-tcp|src={addr[0]}:{addr[1]}|proto=TCP|CRITICAL=LDAPS_PROBE realm=pul-cloud-internal.local")
    try:
        data = conn.recv(512)
        conn.sendall(LDAP_ERR)
    except Exception:
        pass
    finally:
        conn.close()

def serve():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("0.0.0.0", 636))
    s.listen(10)
    while True:
        conn, addr = s.accept()
        threading.Thread(target=handle, args=(conn, addr), daemon=True).start()

if __name__ == "__main__":
    serve()
PYEOF

# ── Systemd services ──────────────────────────────────────────────────────────
declare -A SERVICES=(
    ["pul-decoy-m5-vault-ui"]="${DECOY_DIR}/vault_ui.py"
    ["pul-decoy-m5-keycloak"]="${DECOY_DIR}/keycloak.py"
    ["pul-decoy-m5-cyberark"]="${DECOY_DIR}/cyberark.py"
    ["pul-decoy-m5-teleport"]="${DECOY_DIR}/teleport.py"
    ["pul-decoy-m5-radius-tcp"]="${DECOY_DIR}/radius_tcp.py"
    ["pul-decoy-m5-ldaps-tcp"]="${DECOY_DIR}/ldaps_tcp.py"
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
    for PORT in 8200 8180 4444 9191 1812 636; do
        ufw allow "${PORT}/tcp" comment "Honeytrap M5" >/dev/null 2>&1 || true
    done
fi

echo "============================================================"
echo "  M5 Honeytrap Decoys Active"
echo "  8200 — Fake HashiCorp Vault UI"
echo "  8180 — Fake Keycloak Identity Provider"
echo "  4444 — Fake CyberArk PAM Portal"
echo "  9191 — Fake Teleport Access Proxy"
echo "  1812 — TCP RADIUS Authentication Banner"
echo "  636  — TCP LDAPS Service Banner"
echo "  Logs → ${LOGFILE}"
echo "============================================================"

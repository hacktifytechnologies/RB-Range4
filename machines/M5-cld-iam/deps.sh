#!/usr/bin/env bash
# =============================================================================
# RNG-CLD-01 | M5 — cld-iam | deps.sh
# Ubuntu 22.04 LTS | Requires internet.
# =============================================================================
set -euo pipefail
echo "============================================================"
echo "  RNG-CLD-01 | M5-cld-iam | Dependency Installer"
echo "  Prabal Urja Limited — Operation GRIDFALL"
echo "============================================================"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y --no-install-recommends python3 python3-pip net-tools procps
pip3 install --quiet flask==2.3.3 werkzeug==2.3.7
echo ""
echo "[+] M5 dependencies installed."
echo "    Python : $(python3 --version)"
echo "    Flask  : $(python3 -c 'import flask; print(flask.__version__)')"
echo "[!] Run setup.sh to configure the challenge."

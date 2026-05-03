#!/usr/bin/env bash
# =============================================================================
# RNG-CLD-01 | M1 — cld-webapp | deps.sh
# Installs dependencies for the PUL Cloud Developer Portal (SSRF challenge)
# and the Cloud Metadata Service (IMDS) simulator.
# Ubuntu 22.04 LTS | Requires internet.
# =============================================================================
set -euo pipefail

echo "============================================================"
echo "  RNG-CLD-01 | M1-cld-webapp | Dependency Installer"
echo "  Prabal Urja Limited — Operation GRIDFALL"
echo "============================================================"

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y --no-install-recommends \
    python3 python3-pip net-tools procps curl iproute2 iptables

pip3 install --quiet \
    flask==2.3.3 \
    werkzeug==2.3.7 \
    requests==2.31.0

echo ""
echo "[+] M1 dependencies installed."
echo "    Python  : $(python3 --version)"
echo "    Flask   : $(python3 -c 'import flask; print(flask.__version__)')"
echo "    requests: $(python3 -c 'import requests; print(requests.__version__)')"
echo "[!] Run setup.sh to configure the challenge."

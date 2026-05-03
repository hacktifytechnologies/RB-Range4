#!/usr/bin/env bash
# =============================================================================
# RNG-CLD-01 | M4 — cld-registry | deps.sh
# Installs the distribution/distribution registry binary and Apache utils
# for htpasswd. No Docker daemon needed — image is created via Python.
# Ubuntu 22.04 LTS | Requires internet.
# =============================================================================
set -euo pipefail
echo "============================================================"
echo "  RNG-CLD-01 | M4-cld-registry | Dependency Installer"
echo "  Prabal Urja Limited — Operation GRIDFALL"
echo "============================================================"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y --no-install-recommends \
    wget curl python3 python3-pip net-tools procps apache2-utils

pip3 install --quiet requests==2.31.0

# Distribution/distribution registry — standalone binary, no Docker needed
REGISTRY_VERSION="2.8.3"
echo "[*] Downloading registry v${REGISTRY_VERSION}..."
wget -q "https://github.com/distribution/distribution/releases/download/v${REGISTRY_VERSION}/registry_${REGISTRY_VERSION}_linux_amd64.tar.gz" \
    -O /tmp/registry.tar.gz

mkdir -p /tmp/registry-extract
tar xzf /tmp/registry.tar.gz -C /tmp/registry-extract
cp /tmp/registry-extract/registry /usr/local/bin/registry
chmod +x /usr/local/bin/registry
rm -rf /tmp/registry.tar.gz /tmp/registry-extract

echo ""
echo "[+] M4 dependencies installed."
echo "    Registry: $(/usr/local/bin/registry --version 2>/dev/null | head -1 || echo 'installed')"
echo "[!] Run setup.sh to configure registry and seed the challenge image."

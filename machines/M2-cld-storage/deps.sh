#!/usr/bin/env bash
# =============================================================================
# RNG-CLD-01 | M2 — cld-storage | deps.sh
# Ubuntu 22.04 LTS | Requires internet.
# =============================================================================
set -euo pipefail
echo "============================================================"
echo "  RNG-CLD-01 | M2-cld-storage | Dependency Installer"
echo "  Prabal Urja Limited — Operation GRIDFALL"
echo "============================================================"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y --no-install-recommends wget curl python3 net-tools procps

echo "[*] Downloading MinIO server binary..."
wget -q "https://dl.min.io/server/minio/release/linux-amd64/minio" \
    -O /usr/local/bin/minio
chmod +x /usr/local/bin/minio

echo "[*] Downloading MinIO client (mc)..."
wget -q "https://dl.min.io/client/mc/release/linux-amd64/mc" \
    -O /usr/local/bin/mc
chmod +x /usr/local/bin/mc

echo ""
echo "[+] M2 dependencies installed."
echo "    MinIO : $(/usr/local/bin/minio --version 2>/dev/null | head -1 || echo 'installed')"
echo "    mc    : $(/usr/local/bin/mc --version 2>/dev/null | head -1 || echo 'installed')"
echo "[!] Run setup.sh to configure the challenge."

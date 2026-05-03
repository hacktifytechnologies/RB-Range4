#!/usr/bin/env bash
# =============================================================================
# RNG-CLD-01 | M3 — cld-k8s | deps.sh
# Installs K3s (lightweight Kubernetes). Uses INSTALL_K3S_SKIP_START so
# setup.sh can configure token-auth-file BEFORE the API server starts.
# Ubuntu 22.04 LTS | Requires internet.
# =============================================================================
set -euo pipefail
echo "============================================================"
echo "  RNG-CLD-01 | M3-cld-k8s | Dependency Installer"
echo "  Prabal Urja Limited — Operation GRIDFALL"
echo "============================================================"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y --no-install-recommends curl wget net-tools procps

echo "[*] Downloading K3s (skip start — configured by setup.sh)..."
# INSTALL_K3S_SKIP_START=true installs binary + systemd unit but does NOT start
curl -sfL https://get.k3s.io | INSTALL_K3S_SKIP_START=true sh -

echo ""
echo "[+] M3 dependencies installed."
echo "    K3s: $(/usr/local/bin/k3s --version 2>/dev/null | head -1 || echo 'installed')"
echo "[!] Run setup.sh to configure RBAC and start the cluster."

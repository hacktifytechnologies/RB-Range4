# Solve Guide — Blue Team
## RNG-CLD-01 | M3 — cld-k8s | K8s RBAC Audit & Secrets Protection

## Detection

### 1. K3s API Server Audit Logs
```bash
# K3s API audit log (if enabled) or journalctl
journalctl -u k3s | grep "secrets" | grep -v "watch" | tail -30

# Specifically look for GET on registry-creds
journalctl -u k3s | grep "registry-creds" | grep "200"
```

### 2. Detect Unusual Token Usage
The static token `pul-cloud-ci-runner-token-2024gridfall` should only be used from CI/CD pipeline IPs. Unexpected source IPs using this token indicate compromise:
```bash
journalctl -u k3s | grep "pul-cloud-ci-runner"
# Filter by source IP — any IP outside CI/CD ranges is suspicious
```

### 3. RBAC Review — Identify the Misconfiguration
```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Show what cloud-ci-runner-role grants
kubectl describe role cloud-ci-runner-role -n pul-cloud
# Find "secrets" under resources: and "get,list" under verbs: — THIS IS THE PROBLEM

# Check all roles that have secrets access
kubectl get roles -n pul-cloud -o yaml | grep -A5 "secrets"
```

## Containment
```bash
# 1. Invalidate the stolen static token immediately
# Edit /etc/rancher/k3s/tokens.csv and replace the token value
sudo sed -i 's/pul-cloud-ci-runner-token-2024gridfall/NEW-ROTATED-TOKEN-HERE/' \
    /etc/rancher/k3s/tokens.csv
sudo systemctl restart k3s

# 2. Remove secrets from RBAC role
kubectl edit role cloud-ci-runner-role -n pul-cloud
# Delete the "secrets" resource entry entirely

# 3. Rotate registry-creds secret value
kubectl create secret generic registry-creds \
    --from-literal=username=registry-admin \
    --from-literal=password='NewReg!stry@CLD2025' \
    --from-literal=registry=11.0.2.40:5000 \
    -n pul-cloud --dry-run=client -o yaml | kubectl apply -f -
# Also update htpasswd on M4 registry to match
```

## Remediation
1. **CI/CD runners must not have Secrets access** — use projected service account tokens or external secrets operator
2. Enable Kubernetes Audit Policy to log all Secrets reads to SIEM
3. Replace static long-lived tokens with short-lived, auto-rotating service account tokens (K8s 1.24+ default)
4. Implement Network Policy to restrict which pods can reach the API server
5. Use OPA Gatekeeper or Kyverno to block Role/ClusterRole creation granting secrets access without approval

## Blue Team Checklist
- [ ] Unauthorized Secrets read confirmed in API audit logs
- [ ] Static token rotated in tokens.csv
- [ ] cloud-ci-runner-role patched to remove secrets access
- [ ] registry-creds password rotated (also update M4 htpasswd)
- [ ] db-creds password rotated as precaution
- [ ] Audit policy enabled for ongoing secrets monitoring

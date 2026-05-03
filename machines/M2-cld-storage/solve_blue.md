# Solve Guide — Blue Team
## RNG-CLD-01 | M2 — cld-storage | Misconfigured Bucket Detection & Response

## Detection

### 1. MinIO Access Logs
```bash
journalctl -u pul-minio | grep "pul-cloud-backups/k8s" | tail -30
# Look for: GET /pul-cloud-backups/k8s/cloud-ci-kubeconfig.yaml 200
```

### 2. Detect Unauthenticated Downloads
Any download of `k8s/cloud-ci-kubeconfig.yaml` without `Authorization: AWS4-HMAC-SHA256` header is a red flag since the bucket shouldn't be public:
```bash
journalctl -u pul-minio | grep "cloud-ci-kubeconfig" | grep -v "AKIAPUL2024CLDSVC01"
```

### 3. Check Bucket Policy
```bash
export MC_HOST_pulminio="http://AKIAPUL2024CLDSVC01:pULcLd%2FS3cr3t2024%2FK3y!@127.0.0.1:9000"
mc policy get pulminio/pul-cloud-backups
# If it says "public", this is the misconfiguration
```

## Containment
```bash
# 1. Remove public policy — require authentication for all bucket access
mc anonymous set none pulminio/pul-cloud-backups

# 2. Rotate the K8s token immediately (on M3):
# Delete the static token from /etc/rancher/k3s/tokens.csv and restart K3s
# Or update the token value to invalidate the stolen one

# 3. Move sensitive files out of this bucket entirely:
mc mv pulminio/pul-cloud-backups/k8s/ pulminio/pul-cloud-internal/k8s/
```

## Remediation
1. **Never store credentials, tokens, or kubeconfigs in object storage** — use a secrets manager (Vault, K8s Secrets, AWS Secrets Manager)
2. Enable bucket access logging and alert on any public bucket policy change
3. Implement bucket-level notifications for reads of sensitive key patterns (`*.yaml`, `*kubeconfig*`, `*.key`, `*.pem`)
4. Apply principle of least privilege: the `pul-cloud-role` IAM role should not have permission to set bucket policies
5. Scan all buckets periodically for public access: `mc anonymous list pulminio`

## Blue Team Checklist
- [ ] Unauthorized download of cloud-ci-kubeconfig.yaml confirmed
- [ ] Bucket policy corrected to private
- [ ] K8s SA token (pul-cloud-ci-runner-token-2024gridfall) rotated on M3
- [ ] MinIO credentials (AKIAPUL2024CLDSVC01) rotated
- [ ] All bucket contents audited for other sensitive files
- [ ] Alert rule added for public bucket policy on this MinIO instance

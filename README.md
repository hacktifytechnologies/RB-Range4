# RNG-CLD-01 — Cloud Zone
## Operation GRIDFALL | Prabal Urja Limited Cloud Infrastructure
**Purple Team Cyber Range — 5 Machines | Cloud Kill Chain**

---

## Overview

RNG-CLD-01 is the Cloud Zone of Operation GRIDFALL. Five machines representing a realistic cloud-native infrastructure stack for a fictional energy company (Prabal Urja Limited). The zone simulates a complete lateral movement chain from a developer portal SSRF all the way to Active Directory credential exfiltration.

Each machine has one realistic, intentional misconfiguration. No CTF puzzles — every flaw maps to a documented real-world incident pattern or OWASP/MITRE technique.

**Zone position in the full chain:**
```
RNG-IT-01/02 → RNG-DEV-01 ──► RNG-CLD-01 (this zone) ──► RNG-AD-01
```

---

## Infrastructure

| Machine | Hostname | IP | Port | Role |
|---|---|---|---|---|
| M1 | cld-webapp | 11.0.2.10 | 8080 | Cloud Developer Portal (Flask) |
| M2 | cld-storage | 11.0.2.20 | 9000 | MinIO S3-compatible Storage |
| M3 | cld-k8s | 11.0.2.30 | 6443 | K3s Kubernetes API Server |
| M4 | cld-registry | 11.0.2.40 | 5000 | OCI Container Registry |
| M5 | cld-iam | 11.0.2.50 | 8080 | IAM / Identity Console (Flask) |

**Network:** 11.0.2.0/24 | **OS:** Ubuntu 22.04 LTS (all machines)

---

## Kill Chain Summary

| Step | Machine | Vulnerability | Credential Gained |
|---|---|---|---|
| 1 | M1 | SSRF → Cloud IMDS (T1552.005) | IAM AccessKey + SecretKey |
| 2 | M2 | Public S3 Bucket (T1530) | K8s SA Token (kubeconfig) |
| 3 | M3 | K8s RBAC Over-Privilege (T1552.007) | Container Registry creds |
| 4 | M4 | Hardcoded Image ENV (T1552.001) | IAM service account password |
| 5 | M5 | Broken Access Control (OWASP API5) | AD LDAP bind credentials |

---

## Directory Structure

```
nexus-cloud-range/
├── README.md
├── RANGE-README.md                ← Full deploy + test guide
├── NETWORK_DIAGRAM.md             ← ASCII topology + credential chain
├── AssessmentQuestions.md         ← Red/Blue team Q&A
├── .gitignore
├── github_push.sh
├── machines/
│   ├── M1-cld-webapp/
│   │   ├── deps.sh / setup.sh
│   │   ├── solve_red.md / solve_blue.md
│   │   ├── SITREP / INREP / RED-REPORT
│   ├── M2-cld-storage/    (same structure)
│   ├── M3-cld-k8s/        (same structure)
│   ├── M4-cld-registry/   (same structure)
│   └── M5-cld-iam/        (same structure)
├── Honeytraps/
│   ├── M1-decoys-cld-webapp.sh    ← AWS Console, API GW, Terraform, Cost Explorer, OTEL, Docker TCP
│   ├── M2-decoys-cld-storage.sh   ← Azure Blob, Backup Mgr, DLP, Rclone, Restic, Replication TCP
│   ├── M3-decoys-cld-k8s.sh       ← K8s Dashboard, Grafana, Helm, Prometheus, ArgoCD, etcd TCP
│   ├── M4-decoys-cld-registry.sh  ← Harbor, Artifactory, Snyk, Registry Mirror, Trivy, Replication TCP
│   └── M5-decoys-cld-iam.sh       ← Vault UI, Keycloak, CyberArk, Teleport, RADIUS TCP, LDAPS TCP
└── ttps/
    ├── red_01_cld-webapp_ttp.yml  →  red_05_cld-iam_ttp.yml
```

---

## Deployment Order (per machine)

```bash
sudo bash deps.sh     # Install OS-level dependencies
sudo bash setup.sh    # Configure and start challenge service (self-tests at end)
sudo bash ../../Honeytraps/MX-decoys-<name>.sh   # (optional) start honeytrap decoys
```

---

## AD Zone Connectivity

M5 exfiltrates `svc_ldap:Ld@pB1nd#2025!` from `cyberange.local` (DC: `33.55.55.137`).

**Required pre-config on SRV08-WEB (33.55.55.129):**
- `/admin/` LDAP settings must have Bind DN `CN=svc_ldap,CN=Users,DC=cyberange,DC=local` and Bind Password `Ld@pB1nd#2025!` pointed at `33.55.55.137`
- Player changes server IP to Kali → triggers LDAP Passback
- If your AD range uses a different `svc_ldap` password, update `AD_INTEGRATION` in `M5-cld-iam/setup.sh` before deploying

---

## MITRE ATT&CK Coverage

T1190, T1552.005, T1530, T1613, T1552.007, T1552.001, T1078.004, T1199

# OPERATION GRIDFALL — Master Attack Chain
# Purple Team Exercise | Prabal Urja Limited
# ============================================================
# Full kill chain across all 4 ranges.
# Reference document for facilitators and red team leads.
# ============================================================

---

## Infrastructure Overview

```
┌─────────────────────────────────────────────────────────────────┐
│  RNG-IT-01 — Corporate Gateway Zone  (203.0.x.x / Honeytrap)   │
│  RNG-IT-02 — IT Operations Zone      (203.0.2.x / Gitea/Vault) │
│  RNG-DEV-01 — Development Zone       (pre-existing / Jenkins)  │
│  RNG-CLD-01 — Cloud Zone             (11.0.2.x / AWS-like)     │
│  RNG-AD-01  — Active Directory       (33.55.55.x / Windows)    │
└─────────────────────────────────────────────────────────────────┘
```

---

## Complete Kill Chain

```
[External Attacker]
        │
        ▼
RNG-IT-01: Corporate Gateway Zone
  M1 — Exposed SSH banner fingerprinting
  M2 — Phishing portal / credential harvesting
  M3 — VPN login bruteforce (decoy)
  M4 — Web app — SQLi / XSS decoys
  M5 — File upload portal
        │
        │ Pivot credential: IT-zone-svc / (captured via honeytrap)
        ▼
RNG-IT-02: IT Operations Zone
  M1 — NEXUS IT Portal (helpdesk web app)
  M2 — Gitea — pul-infra-config repo
         └─ git log → commit #2 → .env
              VAULT_ROLE_ID=pul-cicd-role-7a3f9b2c1d4e
              VAULT_SECRET_ID=3b8f2a1c-9d4e-7f6a-2b1c-8d3f9a7e4b2c
  M3 — HashiCorp Vault (AppRole auth)
         └─ vault read secret/pul/deploy/awx-credentials
              awx_user=awx-svc / awx_pass=AwxSvc@PUL2024!
  M4 — Rundeck / Automation server (decoy)
        │
        │ Pivot credential: AWX service account
        ▼
RNG-DEV-01: Development Zone (pre-existing)
  M1 — GitLab / source control
  M2 — Jenkins CI (pipeline enumeration)
  M3 — Docker registry / artifact store
  M4 — Dev database
  M5 — AWX (Ansible automation)
         └─ Job output / inventory vars:
              cloud_portal_url: http://11.0.2.10:8080
              cloud_api_key: pul-cloud-dev-aK8x2mP9!2024
        │
        │ Pivot credential: cloud_api_key → Cloud Portal
        ▼
RNG-CLD-01: Cloud Zone  ◄── BUILT THIS SESSION
  M1 — PUL Cloud Developer Portal (SSRF)
         └─ URL Health Checker → http://169.254.169.254/...
              AccessKeyId:     AKIAPUL2024CLDSVC01
              SecretAccessKey: pULcLd/S3cr3t2024/K3y!
  M2 — MinIO Object Storage (public bucket)
         └─ s3://pul-cloud-backups/k8s/cloud-ci-kubeconfig.yaml
              token: pul-cloud-ci-runner-token-2024gridfall
  M3 — K3s Kubernetes Cluster (RBAC over-privilege)
         └─ kubectl get secret registry-creds -n pul-cloud
              registry-admin : Reg!stry@CLD2024
  M4 — OCI Container Registry (image ENV leak)
         └─ /v2/pul-cloud/platform-svc/blobs/<config-digest>
              CLOUD_IAM_USER=cloud-iam-svc
              CLOUD_IAM_PASS=IAm@CLD!2025
  M5 — PUL Cloud IAM Console (broken access control)
         └─ GET /api/v1/integrations/int-ad-corp-001/export
              svc_ldap : Ld@pB1nd#2025! @ cyberange.local
              DC:         33.55.55.137
              Web admin:  http://33.55.55.129/admin/
        │
        │ Pivot credential: svc_ldap → AD LDAP Passback
        ▼
RNG-AD-01: Active Directory Zone  (pre-existing)
  SRV08-WEB  — IIS + Web Admin Panel (LDAP Passback)
                └─ Change LDAP server → Kali → capture bind request
                   svc_ldap : Ld@pB1nd#2025!   [confirmed in transit]
  SRV09-SQL  — MSSQL Server (IMPERSONATE + xp_cmdshell)
                └─ IMPERSONATE sa → xp_cmdshell → svc_dev shell
                   svc_dev : D3v$3rv!c3#2025
  SRV10-DEV  — Windows Dev Box (service binary hijack)
                └─ CorpBuildSvc binPath hijack → shell as svc_build
                   svc_build : Bu1ld@cc#2025!
  SRV11-JUMP — Jump Server (LAPS + DPAPI)
                └─ LAPS → local admin → DPAPI vault → svc_itadmin
                   svc_itadmin : 1tAdm!nSvc#2025
  DC03       — Domain Controller (AdminSDHolder poisoning)
                └─ WriteDACL AdminSDHolder → SDProp → DA → DCSync
                   Administrator NTLM hash (all domain secrets)
```

---

## Range Network Reference

| Range | Network | Key Hosts |
|---|---|---|
| RNG-IT-01 | 203.0.1.x | 5 decoy machines |
| RNG-IT-02 | 203.0.2.x | Gitea :3000, Vault :8200 |
| RNG-DEV-01 | (existing) | AWX, Jenkins, GitLab |
| RNG-CLD-01 | 11.0.2.x | Portal :8080, MinIO :9000, K8s :6443, Registry :5000, IAM :8080 |
| RNG-AD-01 | 33.55.55.x | DC03: .137, WEB: .129, SQL: .130, DEV: .131, JUMP: .132 |
| Kali (attacker) | 33.55.55.136 | — |

---

## Credential Chain (ordered)

| # | Credential | Source | Used At |
|---|---|---|---|
| 1 | IT-zone svc creds | RNG-IT-01 honeytrap | RNG-IT-02 portal |
| 2 | `VAULT_ROLE_ID` + `VAULT_SECRET_ID` | RNG-IT-02 Gitea `.env` commit | RNG-IT-02 Vault |
| 3 | `awx-svc:AwxSvc@PUL2024!` | RNG-IT-02 Vault secret | RNG-DEV-01 AWX |
| 4 | `cloud_api_key: pul-cloud-dev-aK8x2mP9!2024` | RNG-DEV-01 AWX job output | RNG-CLD-01 M1 |
| 5 | `AKIAPUL2024CLDSVC01` + secret | RNG-CLD-01 M1 IMDS | RNG-CLD-01 M2 |
| 6 | K8s token `pul-cloud-ci-runner-token-2024gridfall` | RNG-CLD-01 M2 bucket | RNG-CLD-01 M3 |
| 7 | `registry-admin:Reg!stry@CLD2024` | RNG-CLD-01 M3 K8s secret | RNG-CLD-01 M4 |
| 8 | `cloud-iam-svc:IAm@CLD!2025` | RNG-CLD-01 M4 image ENV | RNG-CLD-01 M5 |
| 9 | `svc_ldap:Ld@pB1nd#2025!` | RNG-CLD-01 M5 IAM export | RNG-AD-01 SRV08-WEB |
| 10 | `svc_dev:D3v$3rv!c3#2025` | RNG-AD-01 SQL xp_cmdshell | RNG-AD-01 SRV10-DEV |
| 11 | `svc_build:Bu1ld@cc#2025!` | RNG-AD-01 service hijack | RNG-AD-01 SRV11-JUMP (LAPS read) |
| 12 | LAPS password (random) | RNG-AD-01 LDAP via svc_build | RNG-AD-01 SRV11-JUMP local admin |
| 13 | `svc_itadmin:1tAdm!nSvc#2025` | RNG-AD-01 DPAPI | RNG-AD-01 DC03 |
| 14 | `Administrator` NTLM hash | RNG-AD-01 DCSync | Full domain compromise |

---

## MITRE ATT&CK Coverage (Full Operation)

### RNG-CLD-01 (this session)
| Technique | ID | Machine |
|---|---|---|
| Exploit Public-Facing Application | T1190 | M1 |
| Server-Side Request Forgery | T1190 | M1 |
| Cloud Instance Metadata API | T1552.005 | M1 |
| Data from Cloud Storage Object | T1530 | M2 |
| Container and Resource Discovery | T1613 | M3 |
| Credentials from K8s API | T1552.007 | M3 |
| Credentials in Container Image | T1552.001 | M4 |
| Valid Accounts: Cloud Accounts | T1078.004 | M5 |
| Trusted Relationship | T1199 | M5 |

### RNG-AD-01 (pre-existing)
| Technique | ID | Machine |
|---|---|---|
| LDAP Passback | T1557 | SRV08-WEB |
| SQL Stored Procedures (xp_cmdshell) | T1505 | SRV09-SQL |
| Service Binary Path Hijacking | T1574.011 | SRV10-DEV |
| LAPS Credential Access | T1552.006 | SRV11-JUMP |
| DPAPI Credential Dumping | T1555.004 | SRV11-JUMP |
| AdminSDHolder Persistence | T1484.001 | DC03 |
| DCSync | T1003.006 | DC03 |

---

## Facilitator Setup Checklist

### Before every exercise:
- [ ] Run `CLOUD-TEST-PLAYBOOK.md` full end-to-end verify script
- [ ] Run AD range test playbook Steps 0–5 verifications
- [ ] Confirm `svc_ldap:Ld@pB1nd#2025!` authenticates to DC03
- [ ] Confirm SRV08-WEB `/admin/` LDAP config shows `33.55.55.137` as server
- [ ] Confirm LAPS password on SRV11-JUMP is set (if reset, run `gpupdate /force`)
- [ ] Confirm `CorpBuildSvc` binPath is restored on SRV10-DEV
- [ ] Clean SQL Agent test jobs on SRV09-SQL
- [ ] Verify `svc_itadmin` is NOT in Domain Admins (clean starting state)
- [ ] Verify GenericAll ACE on AdminSDHolder is NOT present (clean start)
- [ ] Take VM snapshots after deps.sh on each cloud range machine

### After every exercise:
- [ ] Run AD cleanup scripts (see AD playbook — CLEANUP section)
- [ ] Revert cloud range VMs to post-deps.sh snapshot (fastest reset)
- [ ] Or re-run each cloud machine `setup.sh` (fully idempotent)

---

## Skip Paths (for time-boxed sessions)

| Skip | From | Shortcut | Notes |
|---|---|---|---|
| SKIP-IT | RNG-IT | Use: `svc_ldap:Ld@pB1nd#2025!` directly | Skips full cloud chain |
| SKIP-A | RNG-AD Step 1 | Use C1a/C1b/C1c contingencies | Skips LDAP passback capture |
| SKIP-B | RNG-AD Step 3 | Read ServiceCredentials table in SQL | Skips service hijack |
| SKIP-CLD | RNG-CLD | Use: `cloud-iam-svc:IAm@CLD!2025` directly against M5 | Skips M1–M4 |

For a 4-hour session: Run RNG-CLD-01 M1→M5 + RNG-AD-01 Steps 1–5 only.
For a full-day session: Run complete chain from RNG-IT-02 onward.

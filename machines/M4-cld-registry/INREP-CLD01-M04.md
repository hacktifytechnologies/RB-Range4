# Incident Report — CLD01-M04
## Container Registry Image Inspection — IAM Credential Exposure
**IR Reference:** INREP-CLD01-M04-20241115
**Incident Type:** Credential Exposure via Container Image Metadata
**Affected System:** cld-registry (11.0.2.40) | Distribution v2.8.3
**Severity:** HIGH | **Confidentiality Impact:** HIGH

---

## 1. Incident Summary

The `pul-cloud/platform-svc:latest` container image hosted on the private container registry (11.0.2.40:5000) contains hardcoded IAM service account credentials in its image configuration manifest's `Env` array. These credentials (`cloud-iam-svc:IAm@CLD!2025`) are the login credentials for the PUL Cloud IAM Console on M5 (11.0.2.50:8080). An attacker authenticated with registry credentials stolen from M3 extracted the credentials by fetching the image config blob directly via the Registry v2 API — without pulling or running the container image.

---

## 2. Timeline

| Time (UTC) | Event |
|---|---|
| T+00:00 | Attacker authenticates to registry with registry-admin:Reg!stry@CLD2024 |
| T+00:04 | GET /v2/_catalog — repository enumeration |
| T+00:08 | GET /v2/pul-cloud/platform-svc/tags/list — tag enumeration |
| T+00:11 | GET /v2/pul-cloud/platform-svc/manifests/latest — manifest fetch, extracts config digest |
| T+00:14 | GET /v2/pul-cloud/platform-svc/blobs/sha256:... — **config blob fetch, credentials extracted** |
| T+00:20 | POST /api/v1/auth/login to M5 with cloud-iam-svc:IAm@CLD!2025 — **M5 pivot successful** |

---

## 3. Root Cause

The `platform-svc` Dockerfile uses `ENV` directives to embed service credentials:
```dockerfile
ENV CLOUD_IAM_USER=cloud-iam-svc
ENV CLOUD_IAM_PASS=IAm@CLD!2025
```

This pattern was introduced during initial development for convenience and was never replaced with a runtime secrets injection pattern before the image was pushed to the production registry. Docker/OCI image config blobs are readable by any user with `pull` access to the registry — the credentials are not encrypted or protected within the manifest.

Additionally, no image secret scanning was integrated into the build or push pipeline to catch this class of vulnerability before the image reached the registry.

---

## 4. Impact Assessment

| Component | Impact | Details |
|---|---|---|
| M4 cld-registry | MEDIUM | Credential exposed in image; registry not otherwise compromised |
| M5 cld-iam | HIGH | cloud-iam-svc:IAm@CLD!2025 grants authenticated IAM Console access |
| AD Range | CRITICAL | M5 IAM Console BAC → AD integration export → domain pivot |
| platform-svc app | MEDIUM | If same creds reused elsewhere, broader exposure possible |

---

## 5. Recommendations

1. **Immediate:** Rotate cloud-iam-svc credentials on M5; rebuild image without ENV credentials
2. **Short-term:** Migrate all images to runtime secret injection via Kubernetes Secret environment variable references
3. **Short-term:** Add Trivy/Grype secret scanning as a mandatory CI/CD gate — block pushes on credential detection
4. **Long-term:** Implement image signing (Cosign/Notary v2) to ensure only pipeline-built, scanned images run in production
5. **Long-term:** Registry access audit logging to SIEM with alerts on `_catalog` enumeration from unexpected IPs
6. **Architecture:** Separate registry auth — CI/CD push-only token vs K8s pull-only token; no shared admin

---

## 6. Lessons Learned

Container image ENV variables are frequently overlooked as a credential exposure vector because developers conflate "private registry" with "encrypted content." Registry authentication only controls who can read the image — it does not encrypt the manifest. Any user with registry pull access can extract all ENV variables without running the container. This is a well-known pattern (CVE-2019-5736 era discussions, Docker Hub leaks) but continues to be common in internal registries without CI secret scanning.

# Assessment Questions — RNG-CLD-01 Cloud Zone
## Operation GRIDFALL | Prabal Urja Limited Cloud Infrastructure
**Format:** Purple Team Exercise — 5 machines, sequential kill chain  
**Duration:** 4–6 hours (red) | 2–3 hours (blue)

---

## M1 — cld-webapp (11.0.2.10:8080) — SSRF → IMDS

### Red Team
1. What is the name of the vulnerable feature in the PUL Cloud Developer Portal and what HTTP method/route does it use?
2. What IP address and URL path must you request to enumerate the IAM role name attached to the instance?
3. What is the full IMDS URL that returns the cloud IAM credentials?
4. What are the stolen `AccessKeyId` and `SecretAccessKey` values?
5. How do you confirm these credentials work against M2 MinIO? Provide the exact CLI command.

### Blue Team
1. What log file on M1 records URL Health Checker requests? What field identifies the fetched URL?
2. What source IP does the IMDS log show for a successful SSRF request — the attacker's IP or localhost? Why?
3. Write a bash one-liner to extract all URL_CHECK log entries targeting the 169.254.x.x range.
4. List three specific code changes needed to remediate the SSRF vulnerability in `app.py`.
5. Why is IMDSv2 an effective mitigation for this class of SSRF attack?

---

## M2 — cld-storage (11.0.2.20:9000) — Misconfigured Public Bucket

### Red Team
1. What is the name of the publicly accessible bucket and what MinIO command was used to make it public?
2. What is the full path and filename of the sensitive file in the public bucket?
3. What token value is embedded in the downloaded file, and what Kubernetes user does it authenticate as?
4. What is the K8s API server address found in the kubeconfig?
5. Provide the `curl` command to download the kubeconfig without using any credentials.

### Blue Team
1. What `mc` command lists the current access policy for all buckets on a MinIO instance?
2. What `mc` command removes the public policy from the `pul-cloud-backups` bucket?
3. How would you detect an anonymous (unauthenticated) download of the kubeconfig in MinIO's journald logs?
4. Besides removing the public policy, what is the correct architectural solution for storing Kubernetes credentials?
5. After rotating the K8s token, what other service on M4 must also be updated and why?

---

## M3 — cld-k8s (11.0.2.30:6443) — K8s RBAC Over-Privilege

### Red Team
1. Using `kubectl auth can-i --list`, what unexpected permission does the `cloud-ci-runner` service account have?
2. What are the two secrets in the `pul-cloud` namespace? Name them both.
3. Provide the `kubectl` command that extracts and base64-decodes the registry password from `registry-creds`.
4. What is the decoded username and password from the `registry-creds` secret?
5. Provide the alternative `curl` command (no kubectl) that reads the secret directly from the K8s API.

### Blue Team
1. What specific RBAC resource and verb combination in `cloud-ci-runner-role` constitutes the misconfiguration?
2. What file on the K3s server contains the static authentication token? How do you rotate it?
3. Write the `kubectl patch` or `kubectl edit` command to remove `secrets` from the RBAC role's resources.
4. What Kubernetes admission controller policy (Kyverno or OPA) would prevent this misconfiguration from being deployed in future?
5. Why are static long-lived tokens considered insecure and what should replace them in K8s 1.24+?

---

## M4 — cld-registry (11.0.2.40:5000) — Credentials in Container Image

### Red Team
1. What Registry v2 API endpoint returns the image manifest, and what MIME type header is required?
2. What field in the manifest JSON points to the OCI image configuration blob?
3. What Registry v2 API endpoint downloads a blob given its digest?
4. Inside the config blob JSON, what key path holds the environment variables? (e.g. `config.Env`)
5. What two environment variable values containing credentials are found in the `platform-svc:latest` image?

### Blue Team
1. How does inspecting the config blob differ from doing a full `docker pull`? Why is the config blob approach more dangerous?
2. Name two open-source tools that can scan a container image for hardcoded secrets.
3. What Dockerfile anti-pattern causes this vulnerability, and what is the correct alternative?
4. After rotating the IAM password (`CLOUD_IAM_PASS`), how must the deployed container image be updated?
5. What CI/CD gate would prevent a new image build with credentials in `ENV` from reaching the registry?

---

## M5 — cld-iam (11.0.2.50:8080) — Broken Access Control → AD Pivot

### Red Team
1. What role does `cloud-iam-svc` hold in the IAM Console, and how can you verify this from the JWT?
2. What is the exact API endpoint that is only gated in the UI but not on the server side?
3. What HTTP method and Authorization header format must you use to call this endpoint?
4. List all four critical fields returned in the JSON response from the export endpoint.
5. Provide the `ldapsearch` command that verifies the stolen LDAP credentials against the DC.

### Blue Team
1. What Python decorator is present on the vulnerable route, and what decorator is missing?
2. Write the corrected route definition with proper role enforcement.
3. What OWASP API Security Top 10 (2023) category does this vulnerability fall under?
4. How do you force all existing JWT sessions to expire immediately without restarting the server?
5. Where should AD LDAP credentials be stored instead of in the application config file, and why?

---

## Chain Questions (Full Kill Chain)

1. Trace the complete credential chain from the Dev Zone API key to the final AD LDAP password. List each credential and the machine it was extracted from.
2. At which machine does the attacker first interact with credentials they did **not** need to authenticate with — i.e., credentials that were just left exposed?
3. Which machine's vulnerability allows unauthenticated access (no prior credentials needed) and why?
4. If you could fix only **one** vulnerability in the cloud zone to break the entire kill chain, which machine and which fix would have the highest impact? Justify your answer.
5. The M5 LDAP passback technique uses `svc_ldap` credentials against SRV08-WEB. Explain how changing the LDAP server IP on the SRV08-WEB admin panel causes the credential to be captured — what protocol event occurs and why does the web application initiate the bind?

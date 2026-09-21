# Environment and Configuration Reference

This file is the operational checklist for configuration values used by the Terraria server project.

The current architecture uses Google Cloud for the VM and networking, GitHub Actions for start/stop/status, GitHub OIDC plus Google Workload Identity Federation for authentication, optional DuckDNS, and future Cloud Storage world backups.

Do not commit real secrets to this repository.

## 1. GitHub Actions repository variables

Configure these in:

```text
GitHub repository
→ Settings
→ Secrets and variables
→ Actions
→ Variables
```

| Variable | Required now? | Current / expected value | Purpose |
| --- | --- | --- | --- |
| `GCP_PROJECT_ID` | Yes | `tmpsh-recreation-service` | Google Cloud project containing the VM. |
| `GCP_ZONE` | Yes | `us-central1-f` | Zone containing `terraria-server`. |
| `VM_NAME` | Yes | `terraria-server` | Compute Engine instance controlled by GitHub Actions. |
| `GCP_SERVICE_ACCOUNT` | Yes | `github-terraria-control@tmpsh-recreation-service.iam.gserviceaccount.com` | Service account impersonated through Workload Identity Federation. |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | Yes | Pending creation/verification | Full WIF provider resource name. |
| `DUCKDNS_SUBDOMAIN` | Optional | TBD | DuckDNS subdomain to update after VM start. |
| `WORLD_BACKUP_BUCKET` | Future | TBD | Cloud Storage bucket name used for world backups. |

The WIF provider variable must use the full provider resource name:

```text
projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-actions/providers/github
```

Do not substitute the GCP Project ID for `PROJECT_NUMBER`.

## 2. GitHub Actions repository secrets

Configure these in:

```text
GitHub repository
→ Settings
→ Secrets and variables
→ Actions
→ Secrets
```

| Secret | Required now? | Purpose |
| --- | --- | --- |
| `DUCKDNS_TOKEN` | Optional | Authenticates DuckDNS updates. |
| `TERRARIA_PASSWORD` | Optional / future | Password passed into Terraria server configuration if password protection is enabled. |

Google service-account JSON keys should **not** be stored as GitHub secrets. The intended authentication mechanism is Workload Identity Federation.

## 3. GitHub workflow permissions

The workflow needs read access to repository contents and write access to GitHub's OIDC identity-token permission. That OIDC permission is what allows the Google authentication action to request a short-lived GitHub identity token.

It does not itself grant Google Cloud permissions. Google must separately trust the repository identity and permit service-account impersonation.

## 4. Google Cloud values

These are infrastructure values, not normal process environment variables.

| Setting | Current / expected value | Where configured |
| --- | --- | --- |
| Project ID | `tmpsh-recreation-service` | Google Cloud project |
| Project Number | **TODO / verify** | Google Cloud project details |
| VM name | `terraria-server` | Compute Engine |
| Zone | `us-central1-f` | Compute Engine |
| Machine type | `e2-medium` | Compute Engine |
| Provisioning model | Spot | Compute Engine |
| VPC | `terraria-vpc` | VPC network |
| Subnet | **VERIFY** | VPC network |
| Subnet CIDR | Expected `10.10.0.0/24`, verify | VPC network |
| Terraria port | TCP `7777` | Firewall rule |
| VM network tag | Expected `terraria-server` | Compute Engine network tags |
| Firewall rule | **VERIFY** | VPC firewall |
| External IP | Ephemeral | Compute Engine |
| Service account | `github-terraria-control@tmpsh-recreation-service.iam.gserviceaccount.com` | IAM |
| Current service-account role | Compute Instance Admin (v1) | IAM |

The external IPv4 address is intentionally ephemeral and must not be treated as configuration.

## 5. Workload Identity Federation

Planned values:

```text
Pool ID:
github-actions

Provider ID:
github

Issuer:
https://token.actions.githubusercontent.com
```

Recommended attribute mappings:

```text
google.subject = assertion.sub
attribute.repository = assertion.repository
attribute.repository_owner = assertion.repository_owner
```

Recommended repository restriction:

```text
assertion.repository == 'jerowe-tan/gcp-terraria-server'
```

The resulting provider resource name becomes the GitHub variable `GCP_WORKLOAD_IDENTITY_PROVIDER`.

The external GitHub principal also needs permission to impersonate the service account through Workload Identity Federation.

## 6. Terraform inputs

The files under `terraform/server/` are currently reference scaffolding only. They are not the source of truth for the live infrastructure.

If Terraform is adopted later, use Terraform variables or a non-committed `terraform.tfvars` for non-secret deployment-specific values.

| Terraform variable | Example / status |
| --- | --- |
| `project_id` | `tmpsh-recreation-service` |
| `region` | `us-central1` |
| `zone` | `us-central1-f` |
| `instance_name` | `terraria-server` |
| `machine_type` | `e2-medium` |
| `network_name` | `terraria-vpc` |
| `subnetwork_name` | Verify before use |
| `subnetwork_cidr` | Verify before use; expected `10.10.0.0/24` |
| `terraria_port` | `7777` |
| `service_account_email` | Existing GitHub control service account |
| `github_repository` | `jerowe-tan/gcp-terraria-server` |

Never commit Terraform variable files containing sensitive values, Terraform state, service-account JSON keys, private keys, DuckDNS tokens, or Terraria passwords.

## 7. Future VM/runtime configuration

When Terraria installation automation is added, document each runtime setting here before wiring it into scripts.

| Setting | Storage recommendation | Notes |
| --- | --- | --- |
| World file/name | VM config or deployment config | Must match backup scripts. |
| Max players | VM config | Non-secret. |
| Terraria server password | GitHub secret or VM secret mechanism | Optional. |
| Backup bucket | GitHub variable / VM config | Needed for Cloud Storage backup automation. |
| Backup interval | VM config | Proposed interval is approximately 5–10 minutes. |
| DuckDNS subdomain | GitHub variable | Optional. |
| DuckDNS token | GitHub secret | Optional and sensitive. |

## 8. Configuration still missing

Before the full automation can be considered complete, verify or create:

- GCP Project Number
- Workload Identity Pool and Provider
- WIF service-account impersonation binding
- `GCP_WORKLOAD_IDENTITY_PROVIDER` GitHub variable
- actual subnet name
- actual subnet CIDR
- firewall rule name and TCP 7777 configuration
- world backup bucket
- safe Terraria save/backup/stop mechanism
- optional DuckDNS values

## 9. Current workflow

The initial workflow lives at `.github/workflows/terraria-control.yml`.

It supports `status`, `start`, and `stop`.

The current `stop` operation stops the VM directly and deliberately prints a warning because world-save and backup verification are not implemented yet. Treat that as an interim control path, not the final safe shutdown design.

# Environment and Configuration Reference

This file is the operational checklist for configuration values used by the Terraria server project.

The current architecture uses Google Cloud for the VM and networking, a manual GitHub Actions workflow for start/stop/status, GitHub OIDC plus Google Workload Identity Federation for Google authentication, GitHub Release assets for Terraria world backups, and optional DuckDNS.

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
| `GCP_PROJECT_ID` | Yes | `tmsph-recreation-service` | Google Cloud project containing the VM. |
| `GCP_ZONE` | Yes | `us-central1-f` | Zone containing `terraria-server`. |
| `VM_NAME` | Yes | `terraria-server` | Compute Engine instance controlled by GitHub Actions. |
| `GCP_SERVICE_ACCOUNT` | Yes | `github-terraria-control@tmsph-recreation-service.iam.gserviceaccount.com` | Service account impersonated through Workload Identity Federation. |
| `TERRARIA_VERSION` | Yes for setup | `1458` | Dedicated server package version. |
| `TERRARIA_INSTALL_DIR` | Yes for setup and world | `/opt/terraria` | Server installation directory. |
| `TERRARIA_LINUX_USER` | Yes for setup, world, and backup setup | `jrw` | Linux account that runs Terraria and backup service. |
| `TERRARIA_PORT` | Yes for setup and world | `7777` | Server TCP port. |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | Yes | Pending creation/verification | Full WIF provider resource name. |
| `DUCKDNS_URL` | For DuckDNS | `jrw-terraria.duckdns.org` | Hostname pointed at the VM's current public IPv4 address. |

The manual workflows use these variables:

1. Run `Terraria Server Control` with `start` if the VM is stopped.
2. Run `Terraria Server Setup` to install Terraria and its systemd service. This does not create or start a world.
3. Run `Terraria World` with `create-world` to configure and create the world, then start the server. This action refuses to replace an existing world or different server configuration. If generation failed before creating the `.wld`, rerun with the same `world_name` to repair directory ownership and retry the existing configuration.
4. Run `Terraria World` with `list-worlds` to print world filenames, active status, and sizes in the Actions log. Run `verify` to check an already running server.
5. To remove a world, run `Terraria World` with `delete-world`, set `world_name` to the exact filename from `list-worlds` without `.wld`, and enter `DELETE <world_name>` in `confirm_delete`. This permanently removes the VM's `.wld` and `.wld.bak` files. Deleting the active world stops the server, disables its backup timer, and removes its server configuration; GitHub Release backups remain available. After creating a replacement world, update `TERRARIA_WORLD_PATH` in `/etc/terraria-backup.env` and enable backups again.
6. Run `Terraria Backup Setup` with `install` to install backup tools and render the backup service for `TERRARIA_LINUX_USER`. Configure the VM-local token, then use `enable` to start scheduled backups. The same workflow offers `disable`, `backup-now`, and `status`; see `docs/backup-restore.md`.

`Terraria Server Control → start` updates DuckDNS after the VM starts; `stop` clears its records after the VM stops. `Terraria Domain` offers manual `sync` and `clear`. `sync` requires a running VM and reads its public IPv4 address. DNS supplies a hostname, not a proxy; players connect to `jrw-terraria.duckdns.org:7777`. DNS propagation may take time.

The WIF provider variable must use the full provider resource name:

```text
projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-actions/providers/github
```

Do not substitute the GCP Project ID for `PROJECT_NUMBER`.

## 2. GitHub Actions repository secrets

Configure GitHub Actions secrets in:

```text
GitHub repository
→ Settings
→ Secrets and variables
→ Actions
→ Secrets
```

| Secret | Required now? | Purpose |
| --- | --- | --- |
| `DUCKDNS_TOKEN` | For DuckDNS | Authenticates DuckDNS updates. Store as repository secret, never as variable or committed file. |
| `TERRARIA_PASSWORD` | Optional / future | Password passed into Terraria server configuration if password protection is enabled. |

The Terraria world backup token is **not** a GitHub Actions secret in the current design. It is a VM-local secret documented below.

Google service-account JSON keys should **not** be stored as GitHub secrets. The intended Google authentication mechanism is Workload Identity Federation.

## 3. GitHub workflow permissions

The manual control workflow needs read access to repository contents and write access to GitHub's OIDC identity-token permission. That OIDC permission allows the Google authentication action to request a short-lived GitHub identity token.

It does not itself grant Google Cloud permissions. Google must separately trust the repository identity and permit service-account impersonation.

The workflow is intentionally manual-only. It does not use `push` or `pull_request` as a server start/stop trigger.

## 4. Google Cloud values

| Setting | Current / expected value | Where configured |
| --- | --- | --- |
| Project ID | `tmsph-recreation-service` | Google Cloud project |
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
| Service account | `github-terraria-control@tmsph-recreation-service.iam.gserviceaccount.com` | IAM |
| Current service-account role | Compute Instance Admin (v1) | IAM |

## 5. Workload Identity Federation

Planned values:

```text
Pool ID: github-actions
Provider ID: github
Issuer: https://token.actions.githubusercontent.com
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

## 6. VM-local world backup configuration

The backup system runs on the VM every **10 minutes** using a systemd timer. It uploads changed `.wld` files to a GitHub Release and retains at most **10** automatic backups.

Store configuration at `/etc/terraria-backup.env` with owner `root:root` and mode `0600`.

| Variable | Required? | Value / example | Purpose |
| --- | --- | --- | --- |
| `GITHUB_BACKUP_REPOSITORY` | Yes | `jerowe-tan/gcp-terraria-server` | Repository containing the backup Release. |
| `GITHUB_BACKUP_RELEASE_TAG` | Yes | `terraria-world-backups` | Dedicated Release tag. |
| `GITHUB_BACKUP_RELEASE_NAME` | Recommended | `Terraria World Backups` | Human-readable Release name. |
| `GITHUB_BACKUP_TOKEN` | Yes | VM-only secret | Fine-grained token used to manage Release assets. |
| `TERRARIA_WORLD_PATH` | Yes | Verify after Terraria install | Full path to the active `.wld` file. |
| `BACKUP_FILE_PREFIX` | Recommended | `terraria-world` | Prefix for Release asset filenames. |
| `MAX_WORLD_BACKUPS` | Yes | `10` | Maximum retained automatic backups. |
| `TERRARIA_SAVE_SETTLE_SECONDS` | Recommended | `2` | Delay after an optional save hook. |
| `TERRARIA_SAVE_HOOK` | Future / recommended | executable path | Tells Terraria to save before snapshotting. |
| `TERRARIA_STOP_HOOK` | Future / recommended | executable path | Gracefully stops Terraria before restore. |

The 10-minute interval is configured in `systemd/terraria-world-backup.timer` with `OnUnitActiveSec=10min`.

The GitHub backup token should be a fine-grained token restricted to this repository with `Contents: Read and write`. Do not commit it to Git or Terraform state.

If the repository is public, published Release assets are publicly accessible. Keep the repository private if the world save must remain private.

See `docs/backup-restore.md` for installation and restore procedures.

## 7. Terraform inputs

The files under `terraform/server/` are reference scaffolding only and are not the source of truth for the live infrastructure.

| Terraform variable | Example / status |
| --- | --- |
| `project_id` | `tmsph-recreation-service` |
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

Never commit Terraform state, service-account JSON keys, private keys, GitHub tokens, DuckDNS tokens, or Terraria passwords.

## 8. Configuration still missing

- GCP Project Number
- Workload Identity Pool and Provider
- WIF service-account impersonation binding
- `GCP_WORKLOAD_IDENTITY_PROVIDER` GitHub variable
- actual subnet name and CIDR
- verified firewall rule
- actual Terraria world path
- VM fine-grained GitHub backup token
- tested Terraria save hook
- tested graceful Terraria stop hook
- optional DuckDNS values

## 9. Current workflow

The control workflow at `.github/workflows/terraria-server-control.yml` is manually triggered with `workflow_dispatch` and supports:

```text
status
start
stop
```

There is intentionally no PR-merge, push, or automatic server-start trigger.

The VM-side backup timer is separate from GitHub Actions and runs every 10 minutes while the VM is running. The current GitHub `stop` action does not yet force a final backup immediately before stopping the VM.

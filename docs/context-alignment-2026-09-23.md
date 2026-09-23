# Terraria Server — Context for a New Chat

Use this document as project context. It summarizes the exported ChatGPT conversation through September 23, 2026 and the repository state checked afterward. Treat reported cloud configuration separately from tested workflow results. Verify current GCP and GitHub state before changing live resources.

## Goal and decisions

- Run a Terraria dedicated server on a Google Compute Engine VM. Start and stop the VM manually through GitHub Actions to control cost.
- Keep server installation, world creation, backup setup, and VM power control in separate **manual** workflows. Merging code must not start or stop the VM.
- Use GitHub OIDC and Google Workload Identity Federation (WIF) for Actions authentication. Do not store a long-lived Google service-account JSON key in GitHub.
- Store world backups as assets on a dedicated GitHub Release in the **same repository**, outside Git history. Run a VM-local backup timer every 10 minutes, skip unchanged worlds, and retain at most 10 assets.
- Keep the GitHub token for backup uploads **only on the VM**, in `/etc/terraria-backup.env`. Do not commit it, put it in Terraform state, or turn it into a GitHub Actions secret as part of this design.
- Terraform under `terraform/server/` is reference scaffolding. It is not the source of truth for the existing VM.

## Identifiers and correction

| Item | Current intended value |
| --- | --- |
| Repository | `jerowe-tan/gcp-terraria-server` |
| GCP project ID | `tmsph-recreation-service` |
| GCP project number | `152954806418` |
| VM | `terraria-server` |
| Zone | `us-central1-f` |
| GitHub control service account | `github-terraria-control@tmsph-recreation-service.iam.gserviceaccount.com` |
| WIF provider resource | `projects/152954806418/locations/global/workloadIdentityPools/github-actions/providers/github` |
| Terraria Linux user | `jrw` via repository variable `TERRARIA_LINUX_USER` |
| Terraria port | `7777` |
| Planned install directory | `/opt/terraria` |
| Terraria server package variable | `TERRARIA_VERSION=1458` in the existing workflow configuration |

**Spelling matters:** Earlier chat replies and parts of `docs/gcp-terraria-server-complete-notes.md` use `tmpsh-recreation-service`. That is the old typo. Cloud Shell output and the later successful control workflow established `tmsph-recreation-service`. Check live GitHub variables if authentication fails; do not copy the old spelling from those notes.

Older `docs/terraria-installation.md` examples use Linux user `terraria`. Current GitHub variable is `jrw`; automated scripts derive `/home/jrw/...` paths from that value. `docs/environment-config.md` still contains some historical "pending WIF" checklist text even though the later chat reports WIF working. Treat live GitHub/GCP settings as authoritative.

## Configuration map

GitHub **repository variables** consumed by current workflows. These are intended values from chat and repository configuration, not a fresh read of GitHub Settings:

```text
GCP_PROJECT_ID=tmsph-recreation-service
GCP_ZONE=us-central1-f
VM_NAME=terraria-server
GCP_SERVICE_ACCOUNT=github-terraria-control@tmsph-recreation-service.iam.gserviceaccount.com
GCP_WORKLOAD_IDENTITY_PROVIDER=projects/152954806418/locations/global/workloadIdentityPools/github-actions/providers/github
TERRARIA_VERSION=1458
TERRARIA_INSTALL_DIR=/opt/terraria
TERRARIA_LINUX_USER=jrw
TERRARIA_PORT=7777
```

The five `GCP_*`/`VM_NAME` values drive all workflows. `TERRARIA_VERSION` is used by server installation; install directory, Linux user, and port are used by installation and world setup. Backup setup reads `TERRARIA_LINUX_USER` to render systemd `User=` and `Group=`. `DUCKDNS_SUBDOMAIN` is documented as optional future configuration; current workflows do not consume it.

GitHub **repository secret**: `TERRARIA_PASSWORD` is optional and read only during `Terraria World → create-world`. `DUCKDNS_TOKEN` is documented as optional future configuration and is not consumed by current workflows. Do not put backup token or Google service-account JSON key into GitHub Secrets.

`Terraria World → create-world` takes run inputs `world_name`, `world_size`, `difficulty`, `max_players`, and optional `seed`. These are not repository variables. The backup workflow takes `action` (`install`, `enable`, `disable`, `backup-now`, `status`); world workflow takes `action` (`create-world`, `verify`); control takes `action` (`status`, `start`, `stop`).

VM-local `/etc/terraria-backup.env` contains:

| Name | Intended value or source |
| --- | --- |
| `GITHUB_BACKUP_REPOSITORY` | `jerowe-tan/gcp-terraria-server` |
| `GITHUB_BACKUP_RELEASE_TAG` | `terraria-world-backups` |
| `GITHUB_BACKUP_RELEASE_NAME` | `Terraria World Backups` |
| `GITHUB_BACKUP_TOKEN` | VM-only fine-grained token, value never committed or pasted into context |
| `TERRARIA_WORLD_PATH` | Actual `.wld` path after world creation; read `/etc/terraria/world-path` on VM |
| `BACKUP_FILE_PREFIX` | `terraria-world` |
| `MAX_WORLD_BACKUPS` | `10` |
| `TERRARIA_SAVE_SETTLE_SECONDS` | `2` |
| `TERRARIA_SAVE_HOOK`, `TERRARIA_STOP_HOOK` | Optional; hooks have not been implemented/tested |

Backup environment file should be owned by `root:root` with mode `0600`. Its real token value and real world filename are unknown to this document.

## Reported cloud setup and tested result

- User configured GitHub repository variables, a GitHub OIDC provider in Google WIF, and service-account impersonation. Provider uses GitHub issuer `https://token.actions.githubusercontent.com` and a repository restriction for `jerowe-tan/gcp-terraria-server`.
- User reported configuring OS Login, IAP access, an IAP-only TCP 22 firewall rule, VM network tag, and Service Account User access on the VM's attached service account (`152954806418-compute@developer.gserviceaccount.com`). These are conversation reports; the exported chat does not establish that the new setup workflows have successfully connected through IAP.
- **Tested in prior chat:** `Terraria Server Control` authenticated to Google and successfully ran `status` and `start`. User reported that starting the VM worked.
- **Not established by prior chat:** Terraria installation on the VM, world generation, backup timer activation, successful backup upload, restore, or GitHub-to-VM IAP/SSH execution. Check Actions logs and VM state before claiming any of these work live.

### GCP resources and network

These details come from project notes and the exported conversation. They are a handoff record, not a live inventory:

| Resource | Recorded configuration | Confidence / remaining check |
| --- | --- | --- |
| Project | Display name `Recreation Service`; ID `tmsph-recreation-service`; number `152954806418` | ID typo was resolved in prior chat; number appeared in WIF provider and attached service account. |
| Compute Engine VM | `terraria-server`, zone `us-central1-f`, machine type `e2-medium` (2 visible vCPUs, 4 GB RAM) | VM existence and start/status control were tested; current machine settings need live verification. |
| Provisioning and disk | Spot VM; historical notes say Debian 12, 10 GB standard persistent boot disk, termination action `STOP` | Recorded in older notes; current disk, OS, and termination setting not independently checked here. |
| VM address | Historical internal IP `10.10.0.2`; external IPv4 is ephemeral | Old external IP in notes is stale and must never be treated as current. Read current IP from `status` or `start` workflow. |
| VM identity | Attached default Compute Engine service account `152954806418-compute@developer.gserviceaccount.com` | Identified from screenshot in exported chat; recheck if VM service account changes. |
| VPC | Custom-mode `terraria-vpc`; notes record MTU `1460`, one subnet, global dynamic routing off | Exact subnet name and CIDR remain unverified. `10.10.0.0/24` is an estimate in older docs, not a confirmed value. |
| VM network tag | `terraria-server` | User added network tag while setting up IAP firewall, per conversation. This is a **network tag**, not a Resource Manager tag. |
| Game ingress | TCP `7777` for Terraria players | Existing project design; exact rule name, source ranges, and current enabled state need live verification. |
| IAP SSH ingress | User reported adding rule on `terraria-vpc` targeting tag `terraria-server`, allowing TCP `22` from `35.235.240.0/20` | Rule name `allow-iap-ssh` was proposed; exact saved name and rule state need live verification. Whether any broad public SSH rule remains is unknown. |

No GCS backup bucket is part of the current design. World backup target is GitHub Release assets. Terraform files describe reference resources and were not applied to create the current VM.

### GCP IAM, WIF, and SSH path

| Principal or resource | Recorded role or setting | Purpose / status |
| --- | --- | --- |
| WIF pool and provider | Pool `github-actions`, provider `github`, resource `projects/152954806418/locations/global/workloadIdentityPools/github-actions/providers/github` | Earlier successful control workflow confirms GitHub-to-Google auth worked at that time. |
| GitHub OIDC provider | Issuer `https://token.actions.githubusercontent.com`; default audience | Recorded from setup chat. |
| Provider mappings and condition | `google.subject=assertion.sub`; `attribute.repository=assertion.repository`; `attribute.repository_owner=assertion.repository_owner`; condition `assertion.repository == 'jerowe-tan/gcp-terraria-server'` | Intended restriction to this repository; exact live policy needs recheck. |
| WIF identity on GitHub control service account | `roles/iam.workloadIdentityUser` for repository principal set `principalSet://iam.googleapis.com/projects/152954806418/locations/global/workloadIdentityPools/github-actions/attribute.repository/jerowe-tan/gcp-terraria-server` | Allows impersonation of `github-terraria-control@tmsph-recreation-service.iam.gserviceaccount.com`; control workflow success supports that this worked. |
| GitHub control service account on project | `roles/compute.instanceAdmin.v1` (Compute Instance Admin v1) | Current broad role chosen to get start/stop/status working; least-privilege replacement remains future work. |
| GitHub control service account for VM login | `roles/compute.osAdminLogin` and `roles/iap.tunnelResourceAccessor` | User reported granting these for admin OS Login and IAP tunnel. SSH workflow success not yet established. |
| VM metadata | `enable-oslogin=TRUE` on VM | User reported enabling OS Login. Recheck live metadata before diagnosing SSH. |
| GitHub control service account on VM-attached service account | `roles/iam.serviceAccountUser` on `152954806418-compute@developer.gserviceaccount.com` | User reported granting this on the attached service-account resource, not as a project-wide role. |

Intended remote path: GitHub Actions → GitHub OIDC → Google WIF → GitHub control service account → IAP tunnel → OS Login → `sudo` on VM. Current setup, world, and backup workflows include a preflight that tests IAP SSH and passwordless `sudo` before changing VM files.

**Live inventory unavailable during this handoff:** local `gcloud` has project/account configured, but credential refresh failed without interactive reauthentication. No current VM, firewall, IAM, or WIF settings were read from GCP in this conversation. Values above remain chat and repo records until checked in Cloud Console or with newly authenticated `gcloud`.

## Repository workflows now present

| Workflow | File | Manual actions |
| --- | --- | --- |
| Terraria Server Control | `.github/workflows/terraria-server-control.yml` | `status`, `start`, `stop` |
| Terraria Server Setup | `.github/workflows/terraria-server-setup.yml` | Install Terraria and systemd service only |
| Terraria World | `.github/workflows/terraria-world.yml` | `create-world`, `verify` |
| Terraria Backup Setup | `.github/workflows/terraria-backup-setup.yml` | `install`, `enable`, `disable`, `backup-now`, `status` |

Setup, world, and backup setup use GitHub WIF, check that VM is running, test IAP/OS Login and passwordless `sudo`, then execute repository scripts on the VM. They read configuration from GitHub repository variables. World creation refuses to replace an existing world or server config. `TERRARIA_PASSWORD` is an optional GitHub secret used for world configuration; world settings are manual workflow inputs.

Backup setup reads `TERRARIA_LINUX_USER` and renders `systemd/terraria-world-backup.service` with matching `User=` and `Group=` values. For current configuration, both become `jrw`. `install` installs scripts and timer but does **not** create `/etc/terraria-backup.env` or enable the timer. Configure VM-local token and real world path, then run `enable`; it runs an immediate backup first and enables the 10-minute timer only after success. `disable` stops scheduled backups without deleting existing Release assets. `docs/backup-restore.md` has the steps.

## Repository structure

Current tracked project files, excluding this context file and the exported ChatGPT Markdown:

```text
terraria-server/
├── .chatgpt/
│   └── operations/
│       ├── last-write.json
│       └── ledger.jsonl
├── .github/
│   └── workflows/
│       ├── terraria-backup-setup.yml
│       ├── terraria-server-control.yml
│       ├── terraria-server-setup.yml
│       └── terraria-world.yml
├── docs/
│   ├── backup-restore.md
│   ├── environment-config.md
│   ├── gcp-terraria-server-complete-notes.md
│   └── terraria-installation.md
├── scripts/
│   ├── backup-world-to-github.sh
│   ├── configure-terraria.sh
│   ├── install-backup.sh
│   ├── install-terraria.sh
│   ├── restore-world-from-github.sh
│   └── verify-terraria.sh
├── systemd/
│   ├── terraria-world-backup.service
│   ├── terraria-world-backup.timer
│   └── terraria.service
└── terraform/
    └── server/
        ├── main.tf
        ├── README.md
        └── variables.tf
```

## Backup limits and unfinished safety work

- **Verification on September 23, 2026:** GitHub API reported `0` runs for `terraria-backup-setup.yml`, and backup Release tag `terraria-world-backups` returned `404`. No off-VM backup is visible in the repository. VM timer state could not be read because local `gcloud` credentials need interactive reauthentication.
- Backup script copies a stable on-disk `.wld`, hashes it, uploads changed snapshots to Release tag `terraria-world-backups`, and removes oldest matching assets above 10. Timer interval is 10 minutes while VM is running.
- A tested Terraria **save hook** is not wired. The backup script can snapshot a stable file, but that alone does not force unsaved in-memory game progress onto disk.
- Control workflow `stop` currently stops the VM without forcing a final save, backup, and upload verification.
- Restore script exists and can preserve the previous local world before replacement, but graceful stop hook is not wired. Do not replace a world while Terraria is writing to it.
- GitHub repository currently appears **public** on its GitHub page. Release assets uploaded there would be publicly accessible; use a private repository if world backups must stay private.

## Current handoff state

At the latest local check, branch `main` matched `origin/main` at commit `edfd1f6` (`feat: update workflow`). Only untracked file was the exported chat Markdown. Workflow YAML and Bash syntax were checked locally during implementation; the new setup, world, and backup workflows have **not** been confirmed by a live VM run in this conversation.

Useful references: `docs/environment-config.md`, `docs/backup-restore.md`, `docs/terraria-installation.md`, and exported chat `ChatGPT-Terraria Server MCP Visibility-20260923-1705.md`. The export links to screenshots, but screenshot image contents are not embedded in the Markdown.

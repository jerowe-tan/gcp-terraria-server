# Terraria World Backup and Restore

The primary off-VM backup target is a dedicated **GitHub Release** in the same repository.

This deliberately does **not** commit `.wld` files into Git history. The world files are stored as Release assets instead.

## Backup policy

Current policy:

```text
backup interval: 10 minutes
maximum retained backups: 10
storage target: GitHub Release assets
release tag: terraria-world-backups
```

At most 10 automatic world backups are retained. After a successful upload, the backup script deletes the oldest matching Release asset until only the newest 10 remain.

The script also calculates SHA-256 before uploading. If the world has not changed since the last successful upload, that interval is skipped. Because unchanged worlds are skipped, the 10 retained assets can cover more than 100 minutes of wall-clock time.

## Why Release assets

Release assets live outside normal Git file history, so replacing or deleting old backup assets does not create a long chain of binary `.wld` commits.

If the repository is public, its published release assets are also publicly accessible. Keep the repository private if the world backup should remain private.

## Files

```text
scripts/backup-world-to-github.sh
scripts/restore-world-from-github.sh
scripts/install-backup.sh

systemd/terraria-world-backup.service
systemd/terraria-world-backup.timer
.github/workflows/terraria-backup-setup.yml
```

The systemd timer starts the backup service every 10 minutes while the VM is running.

## GitHub authentication for the VM

Create a fine-grained GitHub personal access token limited to this repository.

Repository permission required for uploading and deleting Release assets:

```text
Contents: Read and write
```

Use the smallest repository scope possible and set an expiration appropriate for the server. Store the value only on the VM in `/etc/terraria-backup.env`; the environment variable name used by the scripts is `GITHUB_BACKUP_TOKEN`.

Do not commit the token or put it in Terraform state.

## VM environment file

Create:

```text
/etc/terraria-backup.env
```

and configure these non-secret values:

```text
GITHUB_BACKUP_REPOSITORY=jerowe-tan/gcp-terraria-server
GITHUB_BACKUP_RELEASE_TAG=terraria-world-backups
GITHUB_BACKUP_RELEASE_NAME=Terraria World Backups

TERRARIA_WORLD_PATH=/home/jrw/.local/share/Terraria/Worlds/OurWorld.wld
BACKUP_FILE_PREFIX=terraria-world
MAX_WORLD_BACKUPS=10
TERRARIA_SAVE_SETTLE_SECONDS=2
```

Also add `GITHUB_BACKUP_TOKEN` to that file and set it to the fine-grained token value.

Optional hooks:

```text
TERRARIA_SAVE_HOOK=/usr/local/bin/terraria-save-world
TERRARIA_STOP_HOOK=/usr/local/bin/terraria-stop-server
```

The save hook should tell the running Terraria process to save before the backup is copied. Until that hook exists, the backup script retries if it sees the world file changing during the copy and uploads only a stable on-disk snapshot.

The stop hook is used by the restore script. A restore must never replace the live world while Terraria is actively writing to it.

Protect the environment file:

```bash
sudo chown root:root /etc/terraria-backup.env
sudo chmod 600 /etc/terraria-backup.env
```

## Install on the VM

After Terraria Server Setup and Terraria World succeed, run **Terraria Backup Setup** with `install`. It reads the GitHub repository variable `TERRARIA_LINUX_USER`, installs the scripts and timer, and renders the backup service to run as that Linux user. For the current value `jrw`, both `User=` and `Group=` become `jrw`.

The workflow does not transfer a GitHub token. Create `/etc/terraria-backup.env` on the VM as shown above. Use the actual world path from `/etc/terraria/world-path`. Then enable the timer:

```bash
sudo systemctl enable --now terraria-world-backup.timer
```

The timer remains disabled until that command runs. Re-running the setup workflow updates backup tools and service user without replacing the VM-local token.

The workflow also offers `backup-now` for an immediate backup and `status` to inspect the timer and recent backup logs. Both require a running VM and an installed backup service.

Check the timer:

```bash
systemctl list-timers terraria-world-backup.timer
```

Check backup logs:

```bash
journalctl -u terraria-world-backup.service
```

## Manual backup

Run an immediate normal backup:

```bash
sudo systemctl start terraria-world-backup.service
```

Normally an unchanged world is skipped. To force an upload, load `/etc/terraria-backup.env` and run `backup-world-to-github.sh --force`.

## List available backups

Load the VM backup environment and run:

```text
restore-world-from-github.sh --list
```

The output is newest-first and includes the Release asset filename.

## Restore the latest backup

First stop the Terraria server process, unless a tested `TERRARIA_STOP_HOOK` is configured.

Then load the backup environment and run:

```text
restore-world-from-github.sh --latest
```

The script requires typing `RESTORE` before replacement. For unattended recovery after the server is definitely stopped, add `--yes`.

## Restore a specific backup

List the backups first, then use the exact asset name:

```text
restore-world-from-github.sh --asset terraria-world-YYYYMMDDTHHMMSSZ-HASH.wld
```

Before replacement, the restore script makes a local emergency copy of the current world under:

```text
/var/lib/terraria-backup/pre-restore-*.wld
```

## STOP workflow status

The GitHub Actions control workflow remains manual-only:

```text
status
start
stop
```

The VM-side 10-minute timer is independent of that workflow.

The current GitHub `stop` action still does **not** force a final backup immediately before Compute Engine is stopped. That can be added later after there is a tested way for GitHub Actions to ask the VM to save and run the backup safely.

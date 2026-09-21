# GCP Terraria Server — Complete Project Notes

> Updated with the currently created Google Cloud resources and the decisions made so far.

---

# 1. Project Goal

Build a very low-cost Terraria dedicated server on **Google Compute Engine** that:

- runs on an `e2-medium` VM
- has about **2 visible vCPUs and 4 GB RAM**
- uses **Spot VM pricing** where acceptable
- can be started/stopped from **GitHub Actions**
- uses **Google Workload Identity Federation** instead of storing a permanent Google JSON key in GitHub
- uses a custom VPC
- uses an ephemeral public IPv4 address
- opens only the Terraria game port that is required
- keeps the Terraria world safe with backups
- optionally uses DuckDNS so players do not need to remember changing IP addresses
- keeps Terraform in the repository for possible future infrastructure-as-code, but does **not currently depend on Terraform**
- minimizes monthly cost by stopping the VM whenever nobody is playing

The central idea is:

> Do not pay for Compute Engine CPU/RAM while nobody is playing.

---

# 2. Current Confirmed Resources

These values are confirmed from the current Google Cloud setup/screenshots.

## Google Cloud project

```text
Project display name:
Recreation Service

Project ID:
tmpsh-recreation-service
```

## GitHub repository

```text
jerowe-tan/gcp-terraria-server
```

## Compute Engine VM

```text
VM name:
terraria-server

Zone:
us-central1-f

Current internal IPv4:
10.10.0.2

Current external IPv4:
34.132.191.173
```

Important:

```text
34.132.191.173
```

is the **current** external IP shown in the screenshot.

Because we are using an ephemeral public IP, this address may change after stop/start or VM recreation.

Do **not** hardcode that address into application configuration.

## Service account

```text
Display name:
Github Terraria Admin

Service account:
github-terraria-control@tmpsh-recreation-service.iam.gserviceaccount.com
```

The service account is enabled.

Current practical role choice:

```text
Compute Instance Admin (v1)
```

This is intentionally broader than the final least-privilege role, but is acceptable for getting the workflow working first.

## VPC

```text
VPC name:
terraria-vpc

Mode:
Custom

MTU:
1460

Subnets:
1

Global dynamic routing:
Off
```

The VPC is successfully created.

The exact subnet name/CIDR is not visible in the latest screenshots, so it should be verified before hardcoding it into documentation.

---

# 3. Current Architecture Decision

The project originally planned to use Terraform to create and destroy the Terraria VM.

The current approach is simpler:

```text
Google Cloud Console
        │
        │ one-time/manual infrastructure configuration
        ▼
Compute Engine Terraria VM
        ▲
        │
        │ start / stop / status / update
        │
GitHub Actions
```

Terraform can remain in the repository for:

- future automation
- documentation
- reproducibility
- learning
- a later migration back to infrastructure-as-code

However:

> Terraform is not required for normal day-to-day server control anymore.

---

# 4. Planned VM Configuration

Current intended machine configuration:

```text
Machine type:
e2-medium

Visible vCPUs:
2

RAM:
4 GB

Provisioning model:
Spot

Zone:
us-central1-f

OS:
Debian 12 currently selected/created
or Ubuntu 24.04 LTS if changed later

Boot disk:
10 GB standard persistent disk

Public IP:
Ephemeral IPv4

Terraria port:
TCP 7777
```

---

# 5. Spot VM

A Spot VM is cheaper than a normal VM because Google can reclaim the VM when it needs the capacity.

Conceptually:

```text
STANDARD VM

higher cost
more reliable
not normally preempted


SPOT VM

lower cost
may be preempted
no guarantee of uninterrupted runtime
```

Google does not preempt Spot VMs on a fixed schedule.

It is not:

```text
every 6 hours
every day
every week
```

Preemption depends on:

- VM family
- machine type
- zone
- current Google capacity
- current demand
- time/day
- other infrastructure conditions

For a casual Terraria server, Spot is attractive because the project is already being designed to tolerate interruption.

---

# 6. Spot Preemption Strategy

We should assume:

> Spot preemption will eventually happen.

Therefore the Terraria world must not rely only on the running game process.

Recommended behavior:

```text
Terraria running
      ↓
periodic save
      ↓
periodic backup/checkpoint
      ↓
Spot preemption
      ↓
attempt final save/backup
```

Current preferred Spot termination behavior:

```text
On VM termination:
STOP
```

rather than automatically deleting the VM.

Why?

```text
If final backup succeeds:
great

If final backup fails:
boot disk still exists
world may still be recoverable
```

After the backup system has been tested thoroughly, a more aggressive delete strategy could be considered.

---

# 7. Cost Strategy

A Google Cloud estimate shown during configuration was roughly:

```text
e2-medium normal compute:
about $24.46/month

Spot discount:
about -$9.78/month

10 GB standard persistent disk:
very small / possibly covered depending on allowance

Estimated Spot VM if running continuously:
roughly $14-$16/month
```

This project is specifically **not intended to run continuously**.

The strategy is:

```text
Want to play?
START VM

Finished playing?
SAVE + BACKUP + STOP VM
```

When the VM is stopped:

```text
CPU billing:
stops

RAM billing:
stops

Boot disk:
remains

Disk/storage billing:
may continue

External ephemeral IP:
may change later
```

The disk is small enough that keeping it is convenient.

---

# 8. Why We No Longer Destroy the VM Every Session

The original design was:

```text
START
→ Terraform creates VM

STOP
→ backup world
→ Terraform destroys VM
```

The current simpler design is:

```text
START
→ gcloud starts existing VM

STOP
→ backup world
→ gcloud stops existing VM
```

This means we keep:

- the operating system
- Terraria installation
- configuration
- swap configuration
- boot disk

and only stop paying for the main CPU/RAM runtime when the VM is stopped.

---

# 9. GitHub Actions as the Control Panel

GitHub Actions should eventually provide:

```text
START
STOP
STATUS
BACKUP
UPDATE
```

The primary manual workflow can use:

```yaml
on:
  workflow_dispatch:
```

with an action dropdown such as:

```text
start
stop
status
```

---

# 10. GitHub → Google Authentication

The workflow must authenticate before it can execute:

```bash
gcloud compute instances start ...
```

or:

```bash
gcloud compute instances stop ...
```

Recommended authentication flow:

```text
GitHub Actions
      ↓
GitHub OIDC token
      ↓
Google Workload Identity Federation
      ↓
Service account impersonation
      ↓
temporary Google credentials
      ↓
gcloud
```

Benefits:

- no permanent Google password in GitHub
- no service-account JSON key in GitHub
- credentials are short-lived
- Google controls exactly which GitHub identity is trusted

---

# 11. Google Cloud Organization Is Not Required

This setup does **not** require:

```text
Google Cloud Organization
```

and does **not** require:

```text
GitHub Organization
```

It can be scoped to:

```text
one GCP project
+
one GitHub repository
```

The repository currently is:

```text
jerowe-tan/gcp-terraria-server
```

---

# 12. Workload Identity Federation Layout

Planned architecture:

```text
GitHub repository
jerowe-tan/gcp-terraria-server
        │
        │ GitHub OIDC
        ▼
Workload Identity Pool
github-actions
        │
        ▼
OIDC Provider
github
        │
        ▼
Service Account
github-terraria-control
        │
        ▼
Compute Engine
terraria-server
```

---

# 13. Workload Identity Pool

Recommended values:

```text
Pool name:
GitHub Actions

Pool ID:
github-actions
```

Provider:

```text
Provider name:
GitHub

Provider ID:
github

Issuer URL:
https://token.actions.githubusercontent.com
```

---

# 14. OIDC Attribute Mapping

Recommended mappings:

```text
google.subject
=
assertion.sub
```

```text
attribute.repository
=
assertion.repository
```

Optionally:

```text
attribute.repository_owner
=
assertion.repository_owner
```

For an even stricter setup later, immutable numeric repository/owner IDs can be used.

---

# 15. Restrict WIF to This Exact Repository

Use an attribute condition similar to:

```text
assertion.repository == 'jerowe-tan/gcp-terraria-server'
```

That means:

```text
jerowe-tan/gcp-terraria-server   ✅

jerowe-tan/another-repository    ❌

someoneelse/gcp-terraria-server  ❌
```

This is an important security boundary.

---

# 16. Workload Identity Provider Resource Name

Once the pool/provider is created, the resource name should look like:

```text
projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-actions/providers/github
```

Important:

`PROJECT_NUMBER` is **not** the same as:

```text
tmpsh-recreation-service
```

The latter is the Project ID.

Do not substitute the service-account unique ID for the Project Number either.

The real Project Number still needs to be copied from the Google Cloud project details.

---

# 17. Service Account

Confirmed service account:

```text
Display name:
Github Terraria Admin

Email:
github-terraria-control@tmpsh-recreation-service.iam.gserviceaccount.com
```

This identity will be used by GitHub Actions after Workload Identity Federation succeeds.

No JSON key should be needed.

---

# 18. IAM Mental Model

The useful IAM model learned during setup is:

```text
Permission
=
one specific action


Role
=
a collection of permissions


Principal
=
the user/service account/workload receiving the role


Resource
=
the thing that the permissions apply to
```

Example:

```text
Principal:
github-terraria-control@tmpsh-recreation-service.iam.gserviceaccount.com

Role:
Compute Instance Admin (v1)

Resource:
tmpsh-recreation-service project
```

---

# 19. Permissions vs Roles

These:

```text
compute.instances.get
compute.instances.start
compute.instances.stop
```

are **permissions**.

They are not roles.

A role can contain those permissions.

Example future role:

```text
Terraria VM Controller
├── compute.instances.get
├── compute.instances.start
└── compute.instances.stop
```

---

# 20. Current IAM Role Choice

Current practical choice:

```text
Compute Instance Admin (v1)
```

This makes initial development easier.

However, this role can do considerably more than:

```text
start
stop
describe
```

Long-term, the service account can be reduced to a custom least-privilege role.

---

# 21. Future Least-Privilege Custom Role

Possible custom role:

```text
Name:
Terraria VM Controller
```

Permissions:

```text
compute.instances.get
compute.instances.start
compute.instances.stop
```

The idea is:

> GitHub should eventually be able to inspect/start/stop the Terraria VM, but not broadly administer unrelated Compute Engine infrastructure.

---

# 22. Current VPC

Confirmed:

```text
VPC:
terraria-vpc

Mode:
Custom

MTU:
1460

Subnet count:
1
```

This VPC was necessary because the project did not have a usable default VPC.

The Google Cloud VM creation screen previously reported:

```text
No more networks available in this project

No network available.
Before you can create an instance, first create a network.
```

So a custom VPC was created.

---

# 23. Subnet

Previously planned values were:

```text
Subnet name:
terraria-subnet

Region:
us-central1

IPv4 range:
10.10.0.0/24
```

The VM currently has:

```text
Internal IP:
10.10.0.2
```

which is consistent with a `10.10.0.0/24` subnet.

However, because the subnet details are not visible in the latest screenshots, verify the actual subnet name/CIDR in Google Cloud before treating the above as final.

---

# 24. VM Network Interface

Desired/expected settings:

```text
Network:
terraria-vpc

Subnetwork:
the Terraria subnet in us-central1

IP stack:
IPv4 single-stack

Primary internal IPv4:
Ephemeral / automatic

External IPv4:
Ephemeral

IP forwarding:
Off

Tier-1 networking:
Off
```

---

# 25. Firewall

Do not enable generic:

```text
HTTP
HTTPS
```

unless something else actually needs them.

Terraria normally uses:

```text
TCP 7777
```

Recommended firewall rule:

```text
Name:
allow-terraria

Network:
terraria-vpc

Direction:
Ingress

Action:
Allow

Target:
Specified target tags

Target tag:
terraria-server

Source IPv4:
0.0.0.0/0

Protocol:
TCP

Port:
7777
```

Then add this network tag to the VM:

```text
terraria-server
```

The VPC screenshot currently shows one firewall rule exists, but the exact rule name/port is not visible there, so verify that it is the intended Terraria rule.

---

# 26. Current Network Layout

```text
Internet
   ↓
Current ephemeral public IP
34.132.191.173
   ↓
Firewall
TCP 7777
   ↓
terraria-vpc
   ↓
Terraria subnet
   ↓
terraria-server
10.10.0.2
```

Remember:

```text
34.132.191.173
```

is temporary and may change.

---

# 27. Ephemeral Public IP

An ephemeral IP is not permanently reserved.

Today:

```text
terraria-server
→ 34.132.191.173
```

After a future stop/start it could become:

```text
terraria-server
→ another public IPv4 address
```

This is fine because the GitHub workflow can read the new IP.

---

# 28. DuckDNS

A domain is not required.

Players can connect with:

```text
PUBLIC_IP:7777
```

Example using the current IP:

```text
34.132.191.173:7777
```

But because the public IP is ephemeral, DuckDNS is convenient.

Example:

```text
ourterraria.duckdns.org:7777
```

Workflow:

```text
START VM
   ↓
read current public IP
   ↓
update DuckDNS
   ↓
players keep using the same hostname
```

---

# 29. DuckDNS GitHub Configuration

Possible repository variable:

```text
DUCKDNS_SUBDOMAIN
```

Possible repository secret:

```text
DUCKDNS_TOKEN
```

The token must never be committed to Git.

DuckDNS remains optional.

---

# 30. Terraria World Persistence

The most important game data is the Terraria world.

Typical file:

```text
world.wld
```

It should not be trusted only to the running Terraria process.

Preferred strategy:

```text
Terraria
    ↓
save world
    ↓
world.wld
    ↓
Cloud Storage / backup
```

Suggested layout:

```text
gs://YOUR_TERRARIA_BUCKET/

worlds/
├── current/
│   └── OurWorld.wld
│
└── backups/
    ├── 2026-09-21-180000-OurWorld.wld
    ├── 2026-09-20-220000-OurWorld.wld
    └── ...
```

Cloud Storage backup automation is still a future step.

---

# 31. Safe STOP Workflow

The final `STOP` workflow should eventually do this:

```text
GitHub STOP
     ↓
authenticate to Google
     ↓
connect/control Terraria process
     ↓
tell Terraria to save
     ↓
gracefully stop Terraria
     ↓
backup world
     ↓
verify backup
     ↓
gcloud compute instances stop terraria-server
```

Important rule:

```text
If backup fails,
do not blindly continue as though everything is safe.
```

---

# 32. Periodic Backup for Spot Safety

Because the server is Spot, relying only on a manual STOP backup is risky.

Recommended future behavior:

```text
Every 5-10 minutes
      ↓
Terraria save/checkpoint
      ↓
copy/upload world backup
```

Then a sudden Spot preemption should lose only a small amount of progress at worst.

The exact backup frequency can be tuned later.

---

# 33. Swap / Virtual RAM

Physical RAM:

```text
4 GB
```

Possible swap:

```text
4 GB
```

Example Linux setup:

```bash
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

echo '/swapfile none swap sw 0 0' \
  | sudo tee -a /etc/fstab
```

Optional:

```bash
echo 'vm.swappiness=10' \
  | sudo tee /etc/sysctl.d/99-terraria.conf

sudo sysctl --system
```

Important:

```text
4 GB RAM + 4 GB swap
≠
8 GB real RAM
```

Swap is an emergency buffer, not a replacement for physical memory.

---

# 34. Operating System

The current VM configuration shown during creation used:

```text
Debian GNU/Linux 12 (bookworm)
```

Earlier architecture discussions considered:

```text
Ubuntu 24.04 LTS
```

Either can run Terraria.

Because the VM now exists, there is no need to change OS merely for consistency unless there is a specific reason.

---

# 35. OS Updates

Typical Debian/Ubuntu maintenance:

```bash
sudo apt-get update
sudo apt-get upgrade -y
```

This can later be included in provisioning scripts or controlled maintenance.

---

# 36. Standard vs Premium Network Tier

Google networking can use different tiers.

Conceptually:

```text
Premium:
more routing through Google's global network

Standard:
more routing through ordinary Internet paths
```

Standard can help reduce cost, but Terraria is latency-sensitive.

Recommended strategy:

```text
test Standard
↓
measure actual gameplay
↓
if latency is bad, try Premium
```

---

# 37. Region / Zone

Current VM:

```text
Region:
us-central1

Zone:
us-central1-f
```

For players in Southeast Asia, a future Singapore deployment could reduce latency:

```text
asia-southeast1
```

However, changing region means considering:

- Spot price
- Spot availability
- latency
- egress/network cost
- migration effort

For now, the server is confirmed in:

```text
us-central1-f
```

---

# 38. GitHub Repository Variables

Once WIF is ready, configure:

```text
GitHub repository:
jerowe-tan/gcp-terraria-server
```

Go to:

```text
Settings
→ Secrets and variables
→ Actions
→ Variables
```

Add:

```text
GCP_PROJECT_ID
tmpsh-recreation-service
```

```text
GCP_SERVICE_ACCOUNT
github-terraria-control@tmpsh-recreation-service.iam.gserviceaccount.com
```

```text
GCP_ZONE
us-central1-f
```

```text
VM_NAME
terraria-server
```

And once WIF is created:

```text
GCP_WORKLOAD_IDENTITY_PROVIDER
projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-actions/providers/github
```

Optional:

```text
DUCKDNS_SUBDOMAIN
```

---

# 39. GitHub Secrets

Possible future secrets:

```text
DUCKDNS_TOKEN
```

Potentially:

```text
TERRARIA_PASSWORD
```

Do **not** create/store a Google service-account JSON key if Workload Identity Federation is working.

---

# 40. GitHub Control Workflow

A good initial workflow:

```yaml
name: Terraria Server Control

on:
  workflow_dispatch:
    inputs:
      action:
        description: "Server action"
        required: true
        type: choice
        options:
          - start
          - stop
          - status

permissions:
  contents: read
  id-token: write

jobs:
  control:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v7

      - name: Authenticate to Google Cloud
        uses: google-github-actions/auth@v3
        with:
          project_id: ${{ vars.GCP_PROJECT_ID }}
          workload_identity_provider: ${{ vars.GCP_WORKLOAD_IDENTITY_PROVIDER }}
          service_account: ${{ vars.GCP_SERVICE_ACCOUNT }}

      - name: Setup Google Cloud CLI
        uses: google-github-actions/setup-gcloud@v3

      - name: Start Terraria VM
        if: inputs.action == 'start'
        run: |
          gcloud compute instances start "${{ vars.VM_NAME }}" \
            --zone="${{ vars.GCP_ZONE }}" \
            --project="${{ vars.GCP_PROJECT_ID }}"

      - name: Stop Terraria VM
        if: inputs.action == 'stop'
        run: |
          gcloud compute instances stop "${{ vars.VM_NAME }}" \
            --zone="${{ vars.GCP_ZONE }}" \
            --project="${{ vars.GCP_PROJECT_ID }}"

      - name: Show Terraria VM status
        if: inputs.action == 'status'
        run: |
          gcloud compute instances describe "${{ vars.VM_NAME }}" \
            --zone="${{ vars.GCP_ZONE }}" \
            --project="${{ vars.GCP_PROJECT_ID }}" \
            --format="table(name,status,networkInterfaces[0].networkIP,networkInterfaces[0].accessConfigs[0].natIP)"
```

---

# 41. Why `id-token: write` Is Needed

GitHub needs:

```yaml
permissions:
  contents: read
  id-token: write
```

`id-token: write` lets the workflow ask GitHub for an OIDC identity token.

It does **not** automatically grant Google Cloud access.

Google still verifies:

```text
Which repository issued the token?

Does it satisfy the WIF condition?

Which service account may it impersonate?

What IAM roles does that service account have?
```

---

# 42. PR Merge / Update Workflow

A separate update workflow can run after code is merged.

Simple:

```yaml
on:
  push:
    branches:
      - main
```

Or explicit PR merge:

```yaml
on:
  pull_request:
    types:
      - closed
    branches:
      - main

jobs:
  update:
    if: github.event.pull_request.merged == true
```

Recommended separation:

```text
terraria-control.yml
→ manual start / stop / status

terraria-update.yml
→ deployment/update after merge
```

This prevents an unrelated commit from automatically turning on the server unnecessarily.

---

# 43. Terraform Status

Terraform is currently:

```text
optional
not used for normal deployment/control
```

It can remain in the repository for future use.

Possible future structure:

```text
terraform/
├── bootstrap/
└── server/
```

But current real infrastructure is being created manually in the Google Cloud Console.

---

# 44. Why Manual Console Setup Is Fine

This approach is currently easier because:

- company/admin authorization may be required
- Terraform would require broader infrastructure permissions
- the VM only needs to be created once
- GitHub only needs operational access afterward

So the current phases are:

```text
Phase 1
Manual GCP infrastructure

Phase 2
Workload Identity Federation

Phase 3
GitHub start/stop/status

Phase 4
Terraria installation/configuration

Phase 5
World backup automation

Phase 6
DuckDNS

Phase 7
Optional Terraform migration later
```

---

# 45. Current Confirmed Variable Sheet

Use this as the quick-reference configuration:

```text
GITHUB_REPOSITORY=
jerowe-tan/gcp-terraria-server

GCP_PROJECT_ID=
tmpsh-recreation-service

VM_NAME=
terraria-server

GCP_ZONE=
us-central1-f

VM_INTERNAL_IP_CURRENT=
10.10.0.2

VM_EXTERNAL_IP_CURRENT=
34.132.191.173

VPC_NAME=
terraria-vpc

GCP_SERVICE_ACCOUNT=
github-terraria-control@tmpsh-recreation-service.iam.gserviceaccount.com

GCP_SERVICE_ACCOUNT_DISPLAY_NAME=
Github Terraria Admin

CURRENT_SERVICE_ACCOUNT_ROLE=
Compute Instance Admin (v1)

GCP_WORKLOAD_IDENTITY_POOL_PLANNED=
github-actions

GCP_WORKLOAD_IDENTITY_PROVIDER_PLANNED=
github

TERRARIA_PORT=
7777
```

Still pending/needs verification:

```text
GCP_PROJECT_NUMBER=
TODO

GCP_WORKLOAD_IDENTITY_PROVIDER=
TODO after WIF provider is created

SUBNET_NAME=
VERIFY

SUBNET_CIDR=
VERIFY

FIREWALL_RULE_NAME=
VERIFY

DUCKDNS_SUBDOMAIN=
OPTIONAL / TODO

WORLD_BACKUP_BUCKET=
TODO

TERRARIA_PASSWORD=
OPTIONAL
```

---

# 46. GitHub Variables Ready to Create

Once the Workload Identity Provider is available:

```text
GCP_PROJECT_ID
=
tmpsh-recreation-service
```

```text
GCP_SERVICE_ACCOUNT
=
github-terraria-control@tmpsh-recreation-service.iam.gserviceaccount.com
```

```text
GCP_ZONE
=
us-central1-f
```

```text
VM_NAME
=
terraria-server
```

```text
GCP_WORKLOAD_IDENTITY_PROVIDER
=
projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-actions/providers/github
```

---

# 47. Final Intended User Experience

Start the server:

```text
GitHub
↓
Actions
↓
Terraria Server Control
↓
Run workflow
↓
start
```

GitHub:

```text
gets OIDC token
↓
authenticates through Google WIF
↓
impersonates Github Terraria Admin service account
↓
runs gcloud
↓
starts terraria-server in us-central1-f
↓
reads current public IP
↓
optionally updates DuckDNS
```

Then players connect.

Stopping:

```text
GitHub
↓
Actions
↓
Terraria Server Control
↓
stop
```

Future safe implementation:

```text
save Terraria world
↓
backup world
↓
verify backup
↓
stop terraria-server
↓
CPU/RAM billing stops
```

---

# 48. Current Security Model

Current practical model:

```text
jerowe-tan/gcp-terraria-server
        ↓
GitHub OIDC
        ↓
Workload Identity Federation
        ↓
github-terraria-control
        ↓
Compute Instance Admin (v1)
        ↓
terraria-server
```

Future hardened model:

```text
jerowe-tan/gcp-terraria-server
        ↓
GitHub OIDC
        ↓
Workload Identity Federation
        ↓
github-terraria-control
        ↓
Terraria VM Controller custom role
        ↓
compute.instances.get
compute.instances.start
compute.instances.stop
        ↓
terraria-server
```

---

# 49. Main Principles Learned

## IAM

```text
Permission = verb/action
Role       = collection of permissions
Principal  = identity
Resource   = thing being controlled
```

## Cost

```text
Do not pay for compute when nobody is playing.
```

## Spot

```text
Assume interruption can eventually happen.
Protect the world.
```

## Security

```text
Get the workflow functioning,
then reduce privileges where practical.
```

## Networking

```text
Terraria needs a VPC/subnet/public path,
but it does not need HTTP/HTTPS.
Only expose what the game actually requires.
```

## Automation

```text
Manual infrastructure creation is fine.
GitHub can still automate everyday operations.
```

---

# 50. Current Project Direction

The current chosen design is:

```text
Manual Google Cloud infrastructure
        +
terraria-server Spot VM
        +
us-central1-f
        +
terraria-vpc
        +
ephemeral IPv4
        +
TCP 7777
        +
Github Terraria Admin service account
        +
Workload Identity Federation
        +
GitHub Actions start/stop/status
        +
future world backups
        +
optional DuckDNS
```

Terraform remains available for future use but is not currently required.

The end goal is a Terraria server that is:

- inexpensive
- easy to start
- easy to stop
- recoverable
- tolerant of Spot interruption
- controllable from GitHub
- free of long-lived Google credentials in GitHub
- understandable enough to maintain manually
- capable of being migrated to Terraform later

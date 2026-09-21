# Terraform server scaffold

This directory is intentionally **reference/pseudo Terraform**.

The current GCP resources were created manually and remain the source of truth. The files here describe a possible future Terraform-managed shape for the server, but they are not safe to apply blindly to the existing project.

Before using Terraform for real:

1. Verify the live subnet name and CIDR.
2. Verify the firewall rule and VM settings in Google Cloud.
3. Decide which existing resources Terraform should own.
4. Add matching resource blocks.
5. Import existing resources into Terraform state.
6. Review the plan until it shows only intentional changes.
7. Only then consider `terraform apply`.

The scaffold deliberately uses `prevent_destroy = true` on the network, subnet, and VM to reduce the risk of accidental destructive experimentation.

See `docs/environment-config.md` for the configuration inventory.

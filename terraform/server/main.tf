/*
REFERENCE / PSEUDO TERRAFORM ONLY

The live Terraria infrastructure was created manually in Google Cloud and is
currently the source of truth. Do not run terraform apply against this file
without first importing/reconciling the existing resources.

This scaffold documents the intended shape of a future Terraform migration.
*/

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

resource "google_compute_network" "terraria" {
  name                    = var.network_name
  auto_create_subnetworks = false

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_compute_subnetwork" "terraria" {
  name          = var.subnetwork_name
  region        = var.region
  network       = google_compute_network.terraria.id
  ip_cidr_range = var.subnetwork_cidr

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_compute_firewall" "allow_terraria" {
  name    = "allow-terraria"
  network = google_compute_network.terraria.name

  direction = "INGRESS"

  allow {
    protocol = "tcp"
    ports    = [tostring(var.terraria_port)]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["terraria-server"]
}

resource "google_compute_instance" "terraria" {
  name         = var.instance_name
  zone         = var.zone
  machine_type = var.machine_type
  tags         = ["terraria-server"]

  scheduling {
    provisioning_model          = "SPOT"
    preemptible                 = true
    automatic_restart           = false
    instance_termination_action = "STOP"
  }

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 10
      type  = "pd-standard"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.terraria.id

    # Empty access_config requests an ephemeral public IPv4 address.
    access_config {}
  }

  # Revisit the VM runtime identity before applying real Terraform.
  service_account {
    scopes = ["cloud-platform"]
  }

  lifecycle {
    prevent_destroy = true
  }
}

output "instance_name" {
  value = google_compute_instance.terraria.name
}

output "instance_zone" {
  value = google_compute_instance.terraria.zone
}

output "public_ip" {
  value = try(google_compute_instance.terraria.network_interface[0].access_config[0].nat_ip, null)
}

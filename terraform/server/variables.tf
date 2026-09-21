variable "project_id" {
  description = "Google Cloud project ID."
  type        = string
  default     = "tmpsh-recreation-service"
}

variable "region" {
  description = "Google Cloud region."
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "Google Cloud zone."
  type        = string
  default     = "us-central1-f"
}

variable "instance_name" {
  description = "Terraria Compute Engine instance name."
  type        = string
  default     = "terraria-server"
}

variable "machine_type" {
  description = "Compute Engine machine type."
  type        = string
  default     = "e2-medium"
}

variable "network_name" {
  description = "Custom VPC name."
  type        = string
  default     = "terraria-vpc"
}

variable "subnetwork_name" {
  description = "Subnet name. Verify the live GCP value before applying Terraform."
  type        = string
  default     = "terraria-subnet"
}

variable "subnetwork_cidr" {
  description = "Subnet IPv4 CIDR. Verify the live GCP value before applying Terraform."
  type        = string
  default     = "10.10.0.0/24"
}

variable "terraria_port" {
  description = "Terraria TCP listening port."
  type        = number
  default     = 7777
}

variable "service_account_email" {
  description = "Existing service account used by GitHub Actions for VM control."
  type        = string
  default     = "github-terraria-control@tmpsh-recreation-service.iam.gserviceaccount.com"
}

variable "github_repository" {
  description = "GitHub repository allowed by Workload Identity Federation."
  type        = string
  default     = "jerowe-tan/gcp-terraria-server"
}

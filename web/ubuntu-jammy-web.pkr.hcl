packer {
  required_version = ">= 1.10.1"
  required_plugins {
    amazon = {
      version = "~> 1.3"
      source  = "github.com/hashicorp/amazon"
    }
    azure = {
      version = "~> 2.1"
      source  = "github.com/hashicorp/azure"
    }
  }
}

data "hcp-packer-version" "ubuntu22-base" {
  bucket_name  = var.base_image_bucket
  channel_name = var.base_image_channel
}

data "hcp-packer-artifact" "ubuntu22-base-aws" {
  bucket_name         = data.hcp-packer-version.ubuntu22-base.bucket_name
  version_fingerprint = data.hcp-packer-version.ubuntu22-base.fingerprint
  platform            = "aws"
  region              = var.aws_region
}

data "hcp-packer-artifact" "ubuntu22-base-azure" {
  bucket_name         = data.hcp-packer-version.ubuntu22-base.bucket_name
  version_fingerprint = data.hcp-packer-version.ubuntu22-base.fingerprint
  platform            = "azure"
  region              = var.az_region
}

locals {
  timestamp  = regex_replace(timestamp(), "[- TZ:]", "")
  image_name = "${var.prefix}-ubuntu22-web-${local.timestamp}"
}

source "amazon-ebs" "base" {
  region        = var.aws_region
  source_ami    = data.hcp-packer-artifact.ubuntu22-base-aws.external_identifier
  instance_type = "t3.small"
  ssh_username  = "ubuntu"
  ami_name      = local.image_name
  ami_regions   = var.aws_region_copies

  tags = {
    owner         = var.owner
    department    = var.department
    source_ami_id = data.hcp-packer-artifact.ubuntu22-base-aws.external_identifier
    Name          = local.image_name
  }
}

source "azure-arm" "base" {
  os_type                   = "Linux"
  build_resource_group_name = var.az_resource_group
  vm_size                   = "Standard_B2s"
  public_ip_sku             = "Standard"

  # Source image
  custom_managed_image_name                = data.hcp-packer-artifact.ubuntu22-base-azure.labels.managed_image_name
  custom_managed_image_resource_group_name = data.hcp-packer-artifact.ubuntu22-base-azure.labels.managed_image_resourcegroup_name

  # Destination image
  managed_image_name                = local.image_name
  managed_image_resource_group_name = var.az_resource_group

  # Compute gallery
  shared_image_gallery_destination {
    subscription         = var.az_subscription_id
    resource_group       = var.az_resource_group
    gallery_name         = var.az_compute_gallery
    image_name           = "ubuntu22-nginx"
    image_version        = formatdate("YYYY.MMDD.hhmm", timestamp())
    replication_regions  = [var.az_region]
    storage_account_type = "Standard_LRS"
  }

  azure_tags = {
    owner      = var.owner
    department = var.department
    build-time = local.timestamp
  }

  use_azure_cli_auth = true
}

build {
  hcp_packer_registry {
    bucket_name = "ubuntu22-nginx"
    description = "Ubuntu 22.04 (jammy) nginx web server image."
    bucket_labels = {
      "owner"          = var.owner
      "dept"           = var.department
      "os"             = "Ubuntu",
      "ubuntu-version" = "22.04",
      "app"            = "nginx",
    }
    build_labels = {
      "build-time" = local.timestamp
    }
  }

  sources = [
    "source.amazon-ebs.base",
    "source.azure-arm.base"
  ]

  # Make sure cloud-init has finished
  provisioner "shell" {
    inline = ["echo 'Wait for cloud-init...' && /usr/bin/cloud-init status --wait"]
  }

  provisioner "shell" {
    environment_vars = ["DEBIAN_FRONTEND=noninteractive"]
    inline = [
      "echo 'debconf debconf/frontend select Noninteractive' | sudo debconf-set-selections",
      "echo 'Installing nginx...' && sudo apt-get -qq -y update >/dev/null",
      "sudo apt-get -qq -y -o \"Dpkg::Options::=--force-confdef\" -o \"Dpkg::Options::=--force-confold\" install nginx >/dev/null",
      "echo 'Adding firewall rule...' && sudo ufw allow http >/dev/null"
    ]
  }
}
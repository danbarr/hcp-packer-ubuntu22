packer {
  required_version = ">= 1.7.7"
  required_plugins {
    amazon = {
      version = "~>1.0"
      source  = "github.com/hashicorp/amazon"
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

locals {
  timestamp  = regex_replace(timestamp(), "[- TZ:]", "")
  image_name = "${var.prefix}-ubuntu22-db-${local.timestamp}"
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

build {
  hcp_packer_registry {
    bucket_name = "ubuntu22-mariadb"
    description = "Ubuntu 22.04 (jammy) MariaDB database server image."
    bucket_labels = {
      "owner"          = var.owner
      "dept"           = var.department
      "os"             = "Ubuntu",
      "ubuntu-version" = "22.04",
      "app"            = "mariadb",
    }
    build_labels = {
      "build-time" = local.timestamp
    }
  }

  sources = [
    "source.amazon-ebs.base",
  ]

  # Make sure cloud-init has finished
  provisioner "shell" {
    inline = ["echo 'Wait for cloud-init...' && /usr/bin/cloud-init status --wait"]
  }

  provisioner "shell" {
    environment_vars = ["DEBIAN_FRONTEND=noninteractive"]
    inline = [
      "echo 'debconf debconf/frontend select Noninteractive' | sudo debconf-set-selections",
      "echo 'Installing mariadb...' && sudo apt-get -qq -y update >/dev/null",
      "sudo apt-get -qy -o \"Dpkg::Options::=--force-confdef\" -o \"Dpkg::Options::=--force-confold\" install mariadb-server mariadb-client >/dev/null",
      "echo 'Adding firewall rule...' && sudo ufw allow 3306/tcp >/dev/null"
    ]
  }
}

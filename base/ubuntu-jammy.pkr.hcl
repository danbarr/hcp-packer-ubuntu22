packer {
  required_version = ">= 1.7.0"
  required_plugins {
    amazon = {
      version = "~>1.0"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

locals {
  timestamp  = regex_replace(timestamp(), "[- TZ:]", "")
  image_name = "${var.prefix}-ubuntu22-${local.timestamp}"
}

data "amazon-ami" "ubuntu-jammy" {
  region = var.aws_region
  filters = {
    name                = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
    virtualization-type = "hvm"
    root-device-type    = "ebs"
  }
  most_recent = true
  owners      = ["099720109477"] # Canonical
}

source "amazon-ebs" "base" {
  region        = var.aws_region
  source_ami    = data.amazon-ami.ubuntu-jammy.id
  instance_type = "t3.small"
  ssh_username  = "ubuntu"
  ami_name      = local.image_name
  ami_regions   = var.aws_region_copies

  tags = {
    owner           = var.owner
    department      = var.department
    source_ami_id   = data.amazon-ami.ubuntu-jammy.id
    source_ami_name = data.amazon-ami.ubuntu-jammy.name
    Name            = local.image_name
  }
}

build {
  hcp_packer_registry {
    bucket_name = "ubuntu22-base"
    description = "Ubuntu 22.04 (jammy) base image."
    bucket_labels = {
      "owner"          = var.owner
      "dept"           = var.department
      "os"             = "Ubuntu",
      "ubuntu-version" = "22.04",
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
    script          = "${path.root}/update.sh"
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
  }

  provisioner "shell" {
    inline = [
      "sudo ufw enable >/dev/null",
      "sudo ufw allow 22 >/dev/null"
    ]
  }
}

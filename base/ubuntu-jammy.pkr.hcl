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

source "azure-arm" "base" {
  os_type                   = "Linux"
  build_resource_group_name = var.az_resource_group
  vm_size                   = "Standard_B2ls_v2"
  public_ip_sku             = "Standard"

  # Source image
  image_publisher = "Canonical"
  image_offer     = "0001-com-ubuntu-server-jammy"
  image_sku       = "22_04-lts-gen2"
  image_version   = "latest"

  # Destination image
  managed_image_name                = local.image_name
  managed_image_resource_group_name = var.az_resource_group

  # Compute gallery
  shared_image_gallery_destination {
    subscription         = var.az_subscription_id
    resource_group       = var.az_resource_group
    gallery_name         = var.az_compute_gallery
    image_name           = "ubuntu22-base"
    image_version        = formatdate("YYYY.MMDD.hhmm", timestamp())
    storage_account_type = "Standard_LRS"

    target_region {
      name = var.az_region
    }
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
    "source.azure-arm.base"
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

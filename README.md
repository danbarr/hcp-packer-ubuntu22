# Demo builds for HCP Packer

A collection of Packer builds for Ubuntu 22.04 (jammy) which publish to the HCP Packer registry. Used to demonstrate image channels, ancestry, revocation, and Terraform integrations.

## Requirements

[Packer](https://www.packer.io/) v1.7.7 or higher.

To build all images, AWS and Azure credentials must be available using one of the following mechanisms:

- [AWS](https://developer.hashicorp.com/packer/plugins/builders/amazon#authentication): environment variables, credential file, or run from an EC2 instance with an instance profile
- [Azure](https://developer.hashicorp.com/packer/plugins/builders/azure#authentication-for-azure): CLI (`az login`), Azure AD interactive login, or run from an Azure VM with a managed identity

An HCP Packer organization, with a "Contributor" service principal key set via the `HCP_CLIENT_ID` and `HCP_CLIENT_SECRET` environment variables.

For Azure, an existing resource group where the builds will take place and images will be published.

## Usage

Copy variables.pkrvars.hcl.example to variables.pkrvars.hcl and customize.

Run the build script:
`./build.sh <build_name>`
Where `build_name` is one of the subfolders - `base` (must be built first), `db`, or `web`.

Or if you're not on Linux/macOS, you can run Packer directly (ex: in a Windows PowerShell):
`packer -var-file ./variables.pkrvars.hcl ./<base|db|web>`

To build only the AWS or Azure images but not both, comment out the provider-specific references in each config file (data source, source block, and entry in the build->sources list).

## Terraform integration

Use the "Use as data source" code generator in the HCP Packer UI to generate a Terraform `hcp_packer_image` data source block.

Example:

```hcl
data "hcp_packer_image" "ubuntu22-nginx" {
  bucket_name     = "ubuntu22-nginx"
  channel         = "production"
  cloud_provider  = "aws"
  region          = "us-east-1"
}

# Then replace your existing references with
# data.hcp_packer_image.ubuntu22-nginx.cloud_image_id
```

To integrate with **Terraform Cloud continuous validation**, add a lifecycle postcondition block to your instance/VM resource:

**AWS:**

```hcl
resource "aws_instance" "my_ec2" {
  # ... resource config ...

  lifecycle {
    postcondition {
      condition     = self.ami == data.hcp_packer_image.ubuntu22-nginx.cloud_image_id
      error_message = "A new source AMI is available in the HCP Packer channel."
    }    
  }
}
```

**Azure:**

```hcl
resource "azurerm_linux_virtual_machine" "my_vm" {
  # ... resource config ...

  lifecycle {
    postcondition {
      condition     = self.source_image_id == data.hcp_packer_image.ubuntu22-nginx.cloud_image_id
      error_message = "A new source image is available in the HCP Packer channel."
    }    
  }
}
```

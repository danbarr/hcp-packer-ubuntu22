# Demo builds for HCP Packer

A collection of Packer builds for Ubuntu 22.04 (jammy) which publish to the HCP Packer registry. Used to demonstrate image channels, ancestry, revocation, and Terraform integrations.

## Requirements

[Packer](https://www.packer.io/) v1.10.1 or higher.

To build all images, AWS credentials must be available using one of the following mechanisms:

- [AWS](https://developer.hashicorp.com/packer/plugins/builders/amazon#authentication): environment variables, credential file, or run from an EC2 instance with an instance profile

An HCP Packer organization, with a "Contributor" service principal key set via the `HCP_CLIENT_ID` and `HCP_CLIENT_SECRET` environment variables.

## Usage

Copy variables.pkrvars.hcl.example to variables.pkrvars.hcl and customize.

Run the build script:
`./build.sh <build_name>`
Where `build_name` is one of the subfolders - `base` (must be built first), `db`, or `web`.

Or if you're not on Linux/macOS, you can run Packer directly (ex: in a Windows PowerShell):
`packer -var-file ./variables.pkrvars.hcl ./<base|db|web>`

## Terraform integration

Use the "Use as data source" code generator in the HCP Packer UI to generate a Terraform `hcp_packer_artifact` data source block.

Example:

```hcl
data "hcp_packer_artifact" "ubuntu22-nginx" {
  bucket_name  = "ubuntu22-nginx"
  channel_name = "production"
  platform     = "aws"
  region       = "us-east-1"
}

# Then replace your existing references with
# data.hcp_packer_artifact.ubuntu22-nginx.external_identifier
```

To integrate with **Terraform Cloud continuous validation**, add a lifecycle postcondition block to your instance resource:

```hcl
resource "aws_instance" "my_ec2" {
  # ... resource config ...

  lifecycle {
    postcondition {
      condition     = self.ami == data.hcp_packer_artifact.ubuntu22-nginx.external_identifier
      error_message = "A new source AMI is available in the HCP Packer channel."
    }    
  }
}
```

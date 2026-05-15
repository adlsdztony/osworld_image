packer {
  required_version = ">= 1.10.0"

  required_plugins {
    amazon = {
      version = ">= 1.3.9"
      source  = "github.com/hashicorp/amazon"
    }

    ansible = {
      version = ">= 1.1.2"
      source  = "github.com/hashicorp/ansible"
    }

    qemu = {
      version = ">= 1.1.1"
      source  = "github.com/hashicorp/qemu"
    }

    vmware = {
      version = ">= 1.1.1"
      source  = "github.com/hashicorp/vmware"
    }
  }
}


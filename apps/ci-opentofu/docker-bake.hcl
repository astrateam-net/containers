target "docker-metadata-action" {}

variable "VERSION" {
  default = "1.1.0"
}

variable "OPENTOFU_VERSION" {
  // renovate: datasource=docker depName=ghcr.io/opentofu/opentofu
  default = "1.11.5"
}

variable "PROXMOX_PROVIDER_VERSION" {
  // renovate: datasource=github-releases depName=bpg/terraform-provider-proxmox
  default = "0.100.0"
}

variable "SOURCE" {
  default = "https://github.com/opentofu/opentofu"
}

group "default" {
  targets = ["image-local"]
}

target "image" {
  inherits = ["docker-metadata-action"]
  args = {
    VERSION                  = "${OPENTOFU_VERSION}"
    PROXMOX_PROVIDER_VERSION = "${PROXMOX_PROVIDER_VERSION}"
  }
  labels = {
    "org.opencontainers.image.source" = "${SOURCE}"
  }
}

target "image-local" {
  inherits = ["image"]
  output   = ["type=docker"]
}

target "image-all" {
  inherits  = ["image"]
  platforms = ["linux/amd64", "linux/arm64"]
}

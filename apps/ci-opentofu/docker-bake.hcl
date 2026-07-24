target "docker-metadata-action" {}

# VERSION is the OpenTofu version, as in every other app here — CI derives the
# published tags from it, so ci-opentofu:1.12.4 now means what it says, and
# Renovate moves the tag by moving this. Previously VERSION was this image's own
# counter and Renovate could not see it, so an auto-merged OpenTofu bump changed
# the contents while VERSION stood still and republished over an existing tag.
variable "VERSION" {
  // renovate: datasource=docker depName=ghcr.io/opentofu/opentofu
  default = "1.12.5"
}

variable "PROXMOX_PROVIDER_VERSION" {
  // renovate: datasource=github-releases depName=bpg/terraform-provider-proxmox
  default = "0.111.1"
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
    VERSION                  = "${VERSION}"
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

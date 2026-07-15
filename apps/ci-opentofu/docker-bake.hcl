target "docker-metadata-action" {}

variable "VERSION" {
  // This image's own version — not upstream-tracked, so Renovate leaves it
  // alone. Bump manually whenever the contents change (OPENTOFU_VERSION, the
  // provider mirror, or the Dockerfile), so the published semver tags point at
  // new content instead of silently overwriting an existing one.
  default = "1.3.0"
}

variable "OPENTOFU_VERSION" {
  // renovate: datasource=docker depName=ghcr.io/opentofu/opentofu
  default = "1.12.4"
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

target "docker-metadata-action" {}

# Primary version = Gerbil. Drives the image tag (semver X.Y.Z / rolling).
variable "VERSION" {
  // renovate: datasource=docker depName=ghcr.io/fosrl/gerbil
  default = "1.5.0"
}

# Traefik binary lifted into the image. Tracks the line Pangolin's reference
# stack pins in its own compose.
variable "TRAEFIK_VERSION" {
  // renovate: datasource=docker depName=traefik
  default = "v3.7.12"
}

variable "S6_OVERLAY_VERSION" {
  // renovate: datasource=github-releases depName=just-containers/s6-overlay versioning=loose extractVersion=^v(?<version>.+)$
  default = "3.2.3.2"
}

variable "SOURCE" {
  default = "https://github.com/fosrl/gerbil"
}

group "default" {
  targets = ["image-local"]
}

target "image" {
  inherits = ["docker-metadata-action"]
  args = {
    VERSION            = "${VERSION}"
    TRAEFIK_VERSION    = "${TRAEFIK_VERSION}"
    S6_OVERLAY_VERSION = "${S6_OVERLAY_VERSION}"
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

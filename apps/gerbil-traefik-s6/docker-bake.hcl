target "docker-metadata-action" {}

# Primary version = Gerbil. Drives the image tag (semver X.Y.Z / rolling).
variable "VERSION" {
  // renovate: datasource=docker depName=ghcr.io/fosrl/gerbil
  default = "1.4.2"
}

# Traefik binary lifted into the image. Pinned to the 3.6 line to match the
# proven standalone traefik_config.yml (badger v1.4.1, entrypoints). Let a
# jump to 3.7.x be a deliberate, separate change.
variable "TRAEFIK_VERSION" {
  // renovate: datasource=docker depName=traefik
  default = "v3.6.22"
}

variable "S6_OVERLAY_VERSION" {
  // renovate: datasource=github-releases depName=just-containers/s6-overlay versioning=loose extractVersion=^v(?<version>.+)$
  default = "3.2.3.0"
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

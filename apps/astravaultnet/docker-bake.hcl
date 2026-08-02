target "docker-metadata-action" {}

variable "VERSION" {
  // renovate: datasource=docker depName=infisical/cli
  default = "0.43.116"
}

# This is our env-driven wrapper around the official infisical/cli image (adds
# a gateway|relay dispatch entrypoint + Docker/Swarm secret support), not a
# stock rebuild — point the OCI source label at the repo that carries the wrapper.
# Supervises the role longruns — a container may run gateway, relay and the
# agent proxy at once, and each is its own foreground process.
variable "S6_OVERLAY_VERSION" {
  // renovate: datasource=github-releases depName=just-containers/s6-overlay versioning=loose extractVersion=^v(?<version>.+)$
  default = "3.2.3.2"
}

variable "SOURCE" {
  default = "https://github.com/astrateam-net/containers"
}

group "default" {
  targets = ["image-local"]
}

target "image" {
  inherits = ["docker-metadata-action"]
  args = {
    VERSION            = "${VERSION}"
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
  inherits = ["image"]
  platforms = [
    "linux/amd64",
    "linux/arm64"
  ]
}

target "docker-metadata-action" {}

variable "VERSION" {
  // renovate: datasource=deb depName=postgresql-18-cron repositoryUrl=https://apt.postgresql.org/pub/repos/apt?suite=trixie-pgdg&components=main extractVersion=^(?<version>\d+\.\d+\.\d+)
  default = "1.6.7"
}

variable "EXT_VERSION" {
  // renovate: datasource=deb depName=postgresql-18-cron repositoryUrl=https://apt.postgresql.org/pub/repos/apt?suite=trixie-pgdg&components=main
  default = "1.6.7-3.pgdg13+1"
}

// Must match the major version and distro of the operand image the Cluster
// runs, or the shared library will not load.
variable "PG_MAJOR" {
  default = "18"
}

variable "DISTRO" {
  default = "trixie"
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
    PG_MAJOR    = "${PG_MAJOR}"
    DISTRO      = "${DISTRO}"
    EXT_VERSION = "${EXT_VERSION}"
  }
  labels = {
    "org.opencontainers.image.source" = "${SOURCE}"
  }
}

target "image-local" {
  inherits = ["image"]
  output = ["type=docker"]
}

target "image-all" {
  inherits = ["image"]
  platforms = ["linux/amd64", "linux/arm64"]
}

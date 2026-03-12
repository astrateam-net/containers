target "docker-metadata-action" {}

variable "VERSION" {
  // renovate: datasource=docker depName=postgres versioning=docker
  default = "17.8.0"
}

variable "PG_VERSION" {
  // renovate: datasource=docker depName=postgres
  default = "17.8"
}

variable "PGBACKREST_VERSION" {
  // renovate: datasource=github-releases depName=pgbackrest/pgbackrest
  default = "2.58.0"
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
    PG_VERSION         = "${PG_VERSION}"
    PGBACKREST_VERSION = "${PGBACKREST_VERSION}"
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

target "docker-metadata-action" {}

variable "VERSION" {
  // renovate: datasource=docker depName=ghcr.io/berriai/litellm versioning=docker
  default = "main-latest@sha256:e0ac5d76ead293c1505587985c8d4360647118cf30d8005963a8f1225ee4d631"
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
    VERSION = "${VERSION}"
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

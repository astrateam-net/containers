target "docker-metadata-action" {}

variable "VERSION" {
  // renovate: datasource=docker depName=quay.io/minio/aistor/minio versioning=regex:^RELEASE\.(?<major>\d{4})-(?<minor>\d{2})-(?<patch>\d{2})T(?<build>\d{2}-\d{2}-\d{2})Z$
  default = "RELEASE.2026-06-06T02-44-06Z"
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
  inherits  = ["image"]
  platforms = ["linux/amd64"]
}

target "docker-metadata-action" {}

variable "VERSION" {
  // renovate: datasource=docker depName=infisical/cli
  default = "0.43.107"
}

# This is our env-driven wrapper around the official infisical/cli image (adds
# a gateway|relay dispatch entrypoint + Docker/Swarm secret support), not a
# stock rebuild — point the OCI source label at the repo that carries the wrapper.
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

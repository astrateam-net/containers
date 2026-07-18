target "docker-metadata-action" {}

variable "VERSION" {
  // renovate: datasource=docker depName=grafana/grafana-enterprise
  default = "13.0.1"
}

# This is our patched image (license trust-root swapped), not stock Grafana
# Enterprise - point the OCI source label at the repo that carries the patch.
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
  output = ["type=docker"]
}

target "image-all" {
  inherits = ["image"]
  platforms = [
    "linux/amd64",
    "linux/arm64"
  ]
}

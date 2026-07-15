target "docker-metadata-action" {}

variable "VERSION" {
  // renovate: datasource=docker depName=ghcr.io/toeverything/affine
  default = "0.27.1"
}

# Our patched image (self-host Team opened), not stock AFFiNE — point the source label at us.
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

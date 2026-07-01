target "docker-metadata-action" {}

variable "VERSION" {
  // renovate: datasource=docker depName=infisical/infisical extractVersion=^v(?<version>.+)$
  default = "0.161.10"
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
  # No platforms pin → buildx builds for the host's native arch, so local runs avoid emulation.
  output = ["type=docker"]
}

target "image-all" {
  inherits  = ["image"]
  platforms = ["linux/amd64", "linux/arm64"]
}

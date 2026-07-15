target "docker-metadata-action" {}

variable "VERSION" {
  // renovate: datasource=docker depName=tolgee/tolgee extractVersion=^v(?<version>.+)$
  default = "3.212.1"
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
  # No platforms pin → buildx builds for the host's native arch (arm64 on Apple Silicon,
  # amd64 in CI), so local runs avoid emulation.
  output = ["type=docker"]
}

target "image-all" {
  inherits  = ["image"]
  platforms = ["linux/amd64", "linux/arm64"]
}

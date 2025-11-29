target "docker-metadata-action" {}

variable "VERSION" {
  // renovate: datasource=github-tags depName=webstudio-is/webstudio/tags
  // GitHub release tag version (e.g., "0.235.0" or "v0.235.0")
  default = "0.235.0"
}

variable "SOURCE" {
  default = "https://github.com/webstudio-is/webstudio"
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


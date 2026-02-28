target "docker-metadata-action" {}

variable "VERSION" {
  // renovate: datasource=docker depName=docker.io/gotenberg/gotenberg
  default = "8.27.0"
}

variable "SOURCE" {
  default = "https://github.com/gotenberg/gotenberg"
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

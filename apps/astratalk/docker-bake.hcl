target "docker-metadata-action" {}

variable "VERSION" {
  // renovate: datasource=docker depName=rasa/rasa-pro
  default = "3.17.4"
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
    "linux/amd64"
  ]
}

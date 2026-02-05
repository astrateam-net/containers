target "docker-metadata-action" {}

variable "VERSION" {
  // renovate: datasource=docker depName=ghcr.io/n8n-io/n8n
  default = "2.7.2"
}

variable "SOURCE" {
  default = "https://github.com/n8n-io/n8n"
}

group "default" {
  targets = ["image-local"]
}

target "image" {
  inherits = ["docker-metadata-action"]
  args = {
    VERSION = "${VERSION}"
    VUE_APP_URL_BASE_API = "/"
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

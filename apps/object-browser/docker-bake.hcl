target "docker-metadata-action" {}

variable "VERSION" {
  // renovate: datasource=github-tags depName=openmaxio-object-browser/tags
  default = "v2.0.1"
}

variable "SOURCE" {
  default = "https://github.com/OpenMaxIO/openmaxio-object-browser"
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
    "linux/amd64"
  ]
}

target "docker-metadata-action" {}

variable "VERSION" {
  // renovate: datasource=github-releases depName=tanainc/tana-desktop-releases
  default = "1.513.2"
}

variable "SOURCE" {
  default = "https://github.com/tanainc/tana-desktop-releases"
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

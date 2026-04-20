target "docker-metadata-action" {}

variable "VERSION" {
  // renovate: datasource=github-releases depName=mrkhachaturov/bird
  default = "0.1.0"
}

variable "SOURCE" {
  default = "https://github.com/mrkhachaturov/bird"
}

group "default" {
  targets = ["image-local"]
}

target "image" {
  inherits = ["docker-metadata-action"]
  # Build from the external source repo — no code is duplicated here.
  context = "${SOURCE}.git#v${VERSION}"
  labels = {
    "org.opencontainers.image.source" = "${SOURCE}"
  }
}

target "image-local" {
  inherits = ["image"]
  output   = ["type=docker"]
}

target "image-all" {
  inherits  = ["image"]
  platforms = ["linux/amd64", "linux/arm64"]
}

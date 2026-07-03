target "docker-metadata-action" {}

# Upstream Pangolin release this fork is built from. Drives the image tag and the
# git tag the source is fetched at (patches must match this version or the build
# fails at `git apply`).
variable "VERSION" {
  // renovate: datasource=github-releases depName=fosrl/pangolin
  default = "1.19.4"
}

variable "SOURCE" {
  default = "https://github.com/fosrl/pangolin"
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
  inherits  = ["image"]
  platforms = ["linux/amd64", "linux/arm64"]
}

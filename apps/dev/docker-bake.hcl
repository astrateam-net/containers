target "docker-metadata-action" {}

# Upstream stable tag. Selects the source fetched and patched at build time,
# the runtime base image (ghcr.io/coder/coder:${VERSION}), and the version
# stamped into the binary. When bumping, regenerate patches/ against the new
# tag (git apply fails the build if a patch no longer matches).
variable "VERSION" {
  // renovate: datasource=docker depName=ghcr.io/coder/coder
  default = "v2.34.3"
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
  output = ["type=docker"]
}

target "image-all" {
  inherits = ["image"]
  platforms = [
    "linux/amd64"
  ]
}

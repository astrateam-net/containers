target "docker-metadata-action" {}

# Upstream Devolutions Gateway version. Selects BOTH the runtime base image
# (devolutions/devolutions-gateway:${VERSION}) and the source tag fetched and
# patched at build time (git tag v${VERSION}). The image tag is bare semver; the
# git tag carries a "v" prefix — the Dockerfile prepends it. When bumping,
# re-verify patches/ against the new tag (git apply fails the build otherwise).
variable "VERSION" {
  // renovate: datasource=docker depName=devolutions/devolutions-gateway
  default = "2026.2.2"
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

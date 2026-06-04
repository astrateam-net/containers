target "docker-metadata-action" {}

variable "VERSION" {
  // renovate: datasource=docker depName=docker.io/stirlingtools/stirling-pdf
  default = "2.11.0"
}

# SOURCE_REF is the git ref on our fork carrying the AstraPDF patch set, applied
# on top of upstream VERSION. Pinned to a tag for reproducibility (the build
# fetches exactly this ref). Bump when re-cutting the patch — rebase the fork
# branch onto a newer upstream tag, push a new astrapdf-<version> tag, and point
# this (and VERSION) at it. Drop SOURCE_REF entirely if upstream merges the PR.
variable "SOURCE_REF" {
  default = "astrapdf-2.11.0"
}

# Fork the patched Stirling source is fetched from at build time.
variable "STIRLING_REPO" {
  default = "https://github.com/mrkhachaturov/Stirling-PDF.git"
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
    VERSION       = "${VERSION}"
    SOURCE_REF    = "${SOURCE_REF}"
    STIRLING_REPO = "${STIRLING_REPO}"
  }
  labels = {
    "org.opencontainers.image.source"   = "${SOURCE}"
    "org.opencontainers.image.revision" = "${SOURCE_REF}"
  }
}

target "image-local" {
  inherits = ["image"]
  platforms = ["linux/amd64"]
  output = ["type=docker"]
}

target "image-all" {
  inherits = ["image"]
  platforms = ["linux/amd64"]
}

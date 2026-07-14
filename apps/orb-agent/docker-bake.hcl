target "docker-metadata-action" {}

variable "VERSION" {
  // renovate: datasource=docker depName=netboxlabs/orb-agent
  default = "2.11.0"
}

# Overlay on netboxlabs/orb-agent (patched snmp-discovery); VERSION tracks
# upstream exactly. Source label points at the repo carrying the overlay.
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
    ORB_REF = "v${VERSION}" # base image tag + source tag from one knob
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
    "linux/amd64",
    "linux/arm64"
  ]
}

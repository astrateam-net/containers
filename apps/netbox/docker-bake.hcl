target "docker-metadata-action" {}

# Base tag = v${VERSION}-${NETBOX_DOCKER_VERSION}; tracked as two independent lines. VERSION drives our tag.
variable "VERSION" {
  // renovate: datasource=docker depName=netboxcommunity/netbox extractVersion=^v(?<version>\d+\.\d+\.\d+)$
  default = "4.6.4"
}

variable "NETBOX_DOCKER_VERSION" {
  // renovate: datasource=github-tags depName=netbox-community/netbox-docker
  default = "5.0.1"
}

# Carried plugins — must stay NetBox-4.6-compatible. netbox_branching MUST be last in PLUGINS
# (see configuration/plugins.py). Dropped in the 4.6 move: nextbox-ui (no 4.6 build), netbox-routing.
variable "NETBOX_ACLS_VERSION" {
  // renovate: datasource=pypi depName=netbox-acls
  default = "2.0.1"
}

# Diode NetBox plugin — write-side API for the Diode ingestion / NetBox Discovery pipeline.
# NetBox 4.6 requires >= 1.12.0 (plugin min_version 4.4.10 / max_version 4.6.99).
variable "NETBOX_DIODE_VERSION" {
  // renovate: datasource=pypi depName=netboxlabs-diode-netbox-plugin
  default = "1.14.0"
}

variable "NETBOX_BRANCHING_VERSION" {
  // renovate: datasource=pypi depName=netboxlabs-netbox-branching
  default = "1.1.1"
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
    VERSION                  = "${VERSION}"
    NETBOX_DOCKER_VERSION    = "${NETBOX_DOCKER_VERSION}"
    NETBOX_ACLS_VERSION      = "${NETBOX_ACLS_VERSION}"
    NETBOX_DIODE_VERSION     = "${NETBOX_DIODE_VERSION}"
    NETBOX_BRANCHING_VERSION = "${NETBOX_BRANCHING_VERSION}"
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

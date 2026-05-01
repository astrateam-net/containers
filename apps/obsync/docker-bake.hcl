target "docker-metadata-action" {}

variable "VERSION" {
  // renovate: datasource=docker depName=couchdb versioning=docker
  default = "3.5.1"
}

variable "DENO_VERSION" {
  // renovate: datasource=github-releases depName=denoland/deno extractVersion=^v(?<version>.*)$
  default = "2.1.4"
}

variable "OBSIDIAN_LIVESYNC_REF" {
  # Pin to a specific commit/tag once we want reproducibility.
  # Tracking 'main' for now — the upstream generate_setupuri.ts changes
  # rarely and is small enough to manually audit on bumps.
  // renovate: datasource=github-tags depName=vrtmrz/obsidian-livesync
  default = "main"
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
    VERSION               = "${VERSION}"
    DENO_VERSION          = "${DENO_VERSION}"
    OBSIDIAN_LIVESYNC_REF = "${OBSIDIAN_LIVESYNC_REF}"
  }
  labels = {
    "org.opencontainers.image.source"      = "${SOURCE}"
    "org.opencontainers.image.title"       = "obsync — CouchDB for Obsidian LiveSync"
    "org.opencontainers.image.description" = "CouchDB ${VERSION} with declarative provisioning + setup URI CLI for Obsidian Self-hosted LiveSync"
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

target "docker-metadata-action" {}

# Upstream stable tag. Selects the source fetched (stablyai/orca @ ${VERSION})
# and patched at build time. When bumping, regenerate patches/ against the new
# tag (git apply fails the build if a patch no longer matches). Renovate skips
# -rc/pre-release tags by default while VERSION is stable.
variable "VERSION" {
  // renovate: datasource=github-releases depName=stablyai/orca
  default = "v1.4.154"
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
    "org.opencontainers.image.source"  = "${SOURCE}"
    "org.opencontainers.image.version" = "${VERSION}"
  }
}

target "image-local" {
  inherits = ["image"]
  output   = ["type=docker"]
}

# amd64 only by design — Orca is an Electron app and an arm64 build under QEMU
# emulation is impractical; no arm64 runtime is targeted.
target "image-all" {
  inherits  = ["image"]
  platforms = ["linux/amd64"]
}

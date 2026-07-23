target "docker-metadata-action" {}

variable "VERSION" {
  // Custom image version - bump manually when Dockerfile/requirements change.
  default = "0.3.0"
}

variable "UBUNTU_VERSION" {
  // renovate: datasource=docker depName=ubuntu
  default = "24.04"
}

variable "GH_RUNNER_VERSION" {
  // renovate: datasource=github-releases depName=actions/runner
  default = "2.336.0"
}

variable "OP_CLI_VERSION" {
  default = "2.33.1"
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
    UBUNTU_VERSION = "${UBUNTU_VERSION}"
    GH_RUNNER_VERSION = "${GH_RUNNER_VERSION}"
    OP_CLI_VERSION = "${OP_CLI_VERSION}"
  }
  labels = {
    "org.opencontainers.image.source" = "${SOURCE}"
  }
}

target "image-local" {
  inherits = ["image"]
  output = ["type=docker"]
}

# amd64 only — deliberately. This runner is self-hosted on the Synology NAS
# (x86_64) and there is no arm64 anywhere in the infra, so an arm64 image has no
# consumer. The arm64 leg was also failing the whole build (arm64 apt pulls from
# ports.ubuntu.com, which timed out from the hosted arm runner), but that is
# secondary and may be transient — the reason it is gone is that nothing runs it.
# Do not re-add until there is an arm64 host in the infra.
target "image-all" {
  inherits = ["image"]
  platforms = [
    "linux/amd64"
  ]
}

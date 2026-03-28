target "docker-metadata-action" {}

variable "VERSION" {
  // Custom image version - bump manually when Dockerfile/requirements change.
  default = "0.1.0"
}

variable "UBUNTU_VERSION" {
  // renovate: datasource=docker depName=ubuntu
  default = "24.04"
}

variable "GH_RUNNER_VERSION" {
  // renovate: datasource=github-releases depName=actions/runner
  default = "2.333.1"
}

variable "SOURCE" {
  default = "https://github.com/actions/runner"
}

group "default" {
  targets = ["image-local"]
}

target "image" {
  inherits = ["docker-metadata-action"]
  args = {
    UBUNTU_VERSION = "${UBUNTU_VERSION}"
    GH_RUNNER_VERSION = "${GH_RUNNER_VERSION}"
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
    "linux/amd64",
    "linux/arm64"
  ]
}

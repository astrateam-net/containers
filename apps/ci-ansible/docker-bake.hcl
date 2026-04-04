target "docker-metadata-action" {}

variable "VERSION" {
  default = "1.1.0"
}

variable "ANSIBLE_CORE_VERSION" {
  // renovate: datasource=pypi depName=ansible-core
  default = "2.20.4"
}

variable "PARAMIKO_VERSION" {
  // renovate: datasource=pypi depName=paramiko
  default = "4.0.0"
}

variable "ANSIBLE_LINT_VERSION" {
  // renovate: datasource=pypi depName=ansible-lint
  default = "26.4.0"
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
    ANSIBLE_CORE_VERSION = "${ANSIBLE_CORE_VERSION}"
    PARAMIKO_VERSION     = "${PARAMIKO_VERSION}"
    ANSIBLE_LINT_VERSION = "${ANSIBLE_LINT_VERSION}"
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

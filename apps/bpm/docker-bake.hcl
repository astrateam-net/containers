target "docker-metadata-action" {}

variable "VERSION" {
  // renovate: datasource=docker depName=docker.io/atlassian/jira-software
  default = "10.7.4"
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
  platforms = ["linux/amd64"]
  output = ["type=docker"]
}

target "image-all" {
  inherits = ["image"]
  platforms = ["linux/amd64"]
}

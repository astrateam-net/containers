target "docker-metadata-action" {}

variable "VERSION" {
  // renovate: datasource=docker depName=docker.io/atlassian/jira-software
  default = "10.7.0"
}

variable "AGENT_VERSION" {
  // renovate: datasource=github-tags depName=haxqer/confluence/tags
  default = "1.3.3"
}

variable "SOURCE" {
  default = "https://bitbucket.org/atlassian-docker/docker-atlassian-jira"
}

group "default" {
  targets = ["image-local"]
}

target "image" {
  inherits = ["docker-metadata-action"]
  args = {
    VERSION = "${VERSION}"
    AGENT_VERSION = "${AGENT_VERSION}"
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

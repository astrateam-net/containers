target "docker-metadata-action" {}

variable "VERSION" {
  // renovate: datasource=github-releases depName=czlonkowski/n8n-mcp extractVersion=^v(?<version>.+)$
  default = "2.47.12"
}

variable "AGENTS_SDK_VERSION" {
  // renovate: datasource=npm depName=n8n-nodes-agents-sdk
  default = "0.5.0"
}

variable "SOURCE" {
  default = "https://github.com/czlonkowski/n8n-mcp"
}

group "default" {
  targets = ["image-local"]
}

target "image" {
  inherits = ["docker-metadata-action"]
  args = {
    VERSION            = "${VERSION}"
    AGENTS_SDK_VERSION = "${AGENTS_SDK_VERSION}"
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

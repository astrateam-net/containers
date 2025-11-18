target "docker-metadata-action" {}

variable "VERSION" {
  // Custom version - update manually when source repo is updated
  // Format: semantic version (e.g., 0.0.1, 0.1.0, 1.0.0)
  default = "0.0.1"
}

variable "SOURCE" {
  default = "https://github.com/penpot/penpot-mcp"
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
  output = ["type=docker"]
}

target "image-all" {
  inherits = ["image"]
  platforms = [
    "linux/amd64",
    "linux/arm64"
  ]
}


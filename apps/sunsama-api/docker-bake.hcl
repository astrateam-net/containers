target "docker-metadata-action" {}

variable "VERSION" {
  // No upstream tags available - using hardcoded version
  // Update VERSION manually when significant upstream changes are pulled
  default = "1.0.0"
}

variable "SOURCE" {
  default = "https://github.com/mrkhachaturov/sunsama-http-api-server"
}

variable "GIT_REF" {
  // Git reference (branch/commit) to build from
  // Default: main branch
  default = "main"
}

group "default" {
  targets = ["image-local"]
}

target "image" {
  inherits = ["docker-metadata-action"]
  args = {
    VERSION = "${VERSION}"
    GIT_REF = "${GIT_REF}"
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


target "docker-metadata-action" {}

variable "VERSION" {
  default = "122474b7d3197822e951d56f43d1b5f14141c335"
}

variable "SOURCE" {
  default = "https://github.com/elie222/inbox-zero"
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
  output   = ["type=docker"]
}

target "image-all" {
  inherits  = ["image"]
  # amd64 only: a Next.js build under arm64 emulation takes hours, and every consumer is amd64.
  platforms = ["linux/amd64"]
}

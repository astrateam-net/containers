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
  inherits   = ["docker-metadata-action"]
  context    = "${SOURCE}.git?ref=${VERSION}&submodules=false"
  dockerfile = "apps/unsubscribe-worker/Dockerfile"
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

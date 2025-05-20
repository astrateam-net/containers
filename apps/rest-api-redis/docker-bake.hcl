target "docker-metadata-action" {}

variable "VERSION" {
  // renovate: datasource=docker depName=git.denvic.ru:5050/pub/rest-api-redis/redisapiweb
  default = "1.0.7"
}

variable "SOURCE" {
  default = "https://git.denvic.ru/pub/rest-api-redis/redisapiweb.git"
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

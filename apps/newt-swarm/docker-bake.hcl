target "docker-metadata-action" {}

# VERSION drives the image tag (passed to docker-metadata-action and to the
# Newt binary via -ldflags). Bump on each rebuild we want a new tag for.
# Format: <upstream-version>-swarm.<n> until upstream merges the feature.
variable "VERSION" {
  default = "1.12.5-swarm.0"
}

# SOURCE_REF is the git ref (branch, tag, or SHA) on the fork to build from.
# Pinned to a SHA on swarm-discovery-stable (= upstream tag 1.12.5 + our
# single feature commit). This isolates the swarm-discovery change against a
# known-good release; the dev-based branch on the fork is for the upstream PR
# only. Bump this SHA when rebasing onto a newer upstream tag.
variable "SOURCE_REF" {
  default = "c0058d936fcd2f17c8b34ae04b1cd7c315d41447"
}

variable "SOURCE" {
  default = "https://github.com/mrkhachaturov/newt"
}

group "default" {
  targets = ["image-local"]
}

target "image" {
  inherits = ["docker-metadata-action"]
  args = {
    VERSION    = "${VERSION}"
    SOURCE_REF = "${SOURCE_REF}"
  }
  labels = {
    "org.opencontainers.image.source"   = "${SOURCE}"
    "org.opencontainers.image.revision" = "${SOURCE_REF}"
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

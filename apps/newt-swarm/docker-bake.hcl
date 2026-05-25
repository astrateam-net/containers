target "docker-metadata-action" {}

# VERSION must match the upstream Newt release this image is built on top of
# (currently 1.12.5). Used for both the image tag and the binary's internal
# version string. Suffixes like -swarm.0 fail upstream's strict X.Y.Z parser
# in updates/updates.go and would print an error on every start; the
# patched-build provenance lives in the image name (newt-swarm) and the OCI
# labels (org.opencontainers.image.revision = SOURCE_REF below) instead.
variable "VERSION" {
  default = "1.12.5"
}

# SOURCE_REF is the git ref (branch, tag, or SHA) on the fork to build from.
# Pinned to a SHA on swarm-discovery-stable (= upstream tag 1.12.5 + our
# single feature commit). This isolates the swarm-discovery change against a
# known-good release; the dev-based branch on the fork is for the upstream PR
# only. Bump this SHA when rebasing onto a newer upstream tag.
variable "SOURCE_REF" {
  default = "8c805bd9f3c957ee04a53567a81252ccefeb4a5c"
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

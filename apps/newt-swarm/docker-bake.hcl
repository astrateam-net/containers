target "docker-metadata-action" {}

# VERSION must match the upstream Newt release this image is built on top of
# (currently 1.20.0). Used for both the image tag and the binary's internal
# version string. Suffixes like -swarm.0 fail upstream's strict X.Y.Z parser
# in updates/updates.go and would print an error on every start; the
# patched-build provenance lives in the image name (newt-swarm) and the OCI
# labels (org.opencontainers.image.revision = SOURCE_REF below) instead.
variable "VERSION" {
  default = "1.20.0"
}

# SOURCE_REF is the git ref (branch, tag, or SHA) on the fork to build from.
# Pinned to a SHA on swarm-v1.20.0 (= upstream tag v1.20.0 + our feature
# commits: cluster-wide Swarm discovery reported by the Raft leader only,
# ported to the moby/moby Docker SDK, plus PREFER_ENDPOINT env-var support). This isolates our changes
# against a known-good release; the dev-based branch on the fork is for the
# upstream PR only. Bump this SHA when rebasing onto a newer upstream tag or
# adding fork commits.
variable "SOURCE_REF" {
  default = "280cc885f594131da83ac20e1ec9b3e99368dfc9"
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

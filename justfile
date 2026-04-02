# containers — custom Docker images published to ghcr.io/astrateam-net
# Modular structure following astrateam-control-plane patterns.

set shell := ["bash", "-euo", "pipefail", "-c"]
set allow-duplicate-recipes := true
set dotenv-load := false

mod core '.just/core.just'
mod build '.just/build.just'
mod sync '.just/sync.just'

import '.just/test.just'
import? '.just/local.just'

default:
  @just --list

# Core

[group("core")]
[doc("Initialize the project (download goss/dgoss)")]
init:
  @just core::init

# Build

[group("build")]
[doc("Build and test an app locally via Docker Buildx")]
local-build app:
  @just build::local-build {{app}}

[group("build")]
[doc("Trigger a remote build via GitHub Actions")]
remote-build app release="false":
  @just build::remote-build {{app}} {{release}}

# CI

[group("ci")]
[doc("Generate app labels in the labels config file")]
generate-app-labels:
  @just core::generate-app-labels

# Sync

[group("sync")]
[doc("Sync Confluence entrypoints and assets from upstream")]
sync-wiki-upstream:
  @just sync::wiki

[group("sync")]
[doc("Sync Jira entrypoints and assets from upstream")]
sync-agile-upstream:
  @just sync::agile

target "docker-metadata-action" {}

variable "VERSION" {
  // renovate: datasource=docker depName=grafana/grafana-enterprise
  default = "13.0.1"
}

variable "SOURCE" {
  default = "https://github.com/astrateam-net/containers"
}

// Plugin set shipped with the image. Entries are `id` or `id@version`.
variable "PLUGINS" {
  default = "elasticsearch,grafana-cloudflare-datasource,grafana-exploretraces-app,grafana-gitlab-datasource,grafana-jira-datasource,grafana-llm-app,grafana-lokiexplore-app,grafana-metricsdrilldown-app,grafana-pyroscope-app,volkovlabs-echarts-panel,grafana-enterprise-logs-app,grafana-metrics-enterprise-app,grafana-enterprise-traces-app"
}

// Build fails if any of these is not processed.
variable "PLUGINS_EE" {
  default = "grafana-cloudflare-datasource,grafana-gitlab-datasource,grafana-jira-datasource"
}

group "default" {
  targets = ["image-local"]
}

target "image" {
  inherits = ["docker-metadata-action"]
  args = {
    VERSION    = "${VERSION}"
    PLUGINS    = "${PLUGINS}"
    PLUGINS_EE = "${PLUGINS_EE}"
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

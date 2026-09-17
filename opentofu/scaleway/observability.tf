# Observability — docs/scaleway/cloud-observability.md.
#
# Deliberately absent: the alert manager, its contacts, preconfigured alerts,
# data exports and dashboards. Alerting is one Alertmanager for four clouds,
# and Scaleway's is regionalised and blocks Grafana's own — so configuring it
# here would split the estate's alerting in two.

# Scaleway's own metrics and logs land in Cockpit for free, with a dashboard
# per product. The central observability cluster reads them out by federating
# the data source, which needs a token that can query and nothing else.
#
# Writing is what costs money on Cockpit — ~2.5x GKE's rate per sample — so
# this token is deliberately unable to do it. Workload metrics stay in the
# socle's own Prometheus.
resource "scaleway_cockpit_token" "observability" {
  count = var.cockpit_token_enabled ? 1 : 0

  project_id = var.project_id
  name       = "${var.cluster_name}-observability-read"

  scopes {
    query_metrics = true
    query_logs    = true
    query_traces  = true

    write_metrics = false
    write_logs    = false
    write_traces  = false

    # Recording and alerting rules belong to the socle's own Prometheus and
    # Alertmanager, not to Cockpit.
    setup_metrics_rules = false
    setup_logs_rules    = false
    setup_alerts        = false
  }
}

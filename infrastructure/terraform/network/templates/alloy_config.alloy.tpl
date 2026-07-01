logging {
  level  = "info"
  format = "logfmt"
}

// Host health metrics (CPU/mem/disk/net) for every network host — nat,
// wireguard, and reverse-proxy all render on the "Ahara Network Health"
// dashboard via the instance label. This is unconditional (all three hosts),
// unlike the Lambda OTLP-receiver stack below which is reverse-proxy-only.
// On the WireGuard host, wg_textfile_dir also points this exporter at the
// WireGuard tunnel-health textfile metrics (see wg_metrics_textfile.sh.tpl).
prometheus.exporter.unix "host" {
  include_exporter_metrics = false

  disable_collectors = ["mdadm", "nfs", "nfsd", "xfs", "zfs"]

%{ if wg_textfile_dir != "" ~}
  textfile {
    directory = "${wg_textfile_dir}"
  }
%{ endif ~}
}

discovery.relabel "host" {
  targets = prometheus.exporter.unix.host.targets

  rule {
    target_label = "instance"
    replacement  = "${host_role}-host"
  }
  rule {
    target_label = "host_role"
    replacement  = "${host_role}"
  }
  rule {
    target_label = "job"
    replacement  = "host-metrics"
  }
}

prometheus.scrape "host" {
  targets         = discovery.relabel.host.output
  forward_to      = [prometheus.remote_write.victoriametrics.receiver]
  scrape_interval = "30s"
}

// Metrics remote-write to TrueNAS VictoriaMetrics, authenticated with the
// Cognito M2M ingest token. Unconditional (all three hosts feed into this —
// host metrics above always; the Lambda OTLP pipeline below, reverse-proxy
// only, also forwards here when otlp_gateway_enabled).
prometheus.remote_write "victoriametrics" {
  endpoint {
    url = "http://${truenas_observability_host}:${truenas_victoriametrics_port}/api/v1/write"

    oauth2 {
      client_id     = sys.env("OBS_INGEST_CLIENT_ID")
      client_secret = sys.env("OBS_INGEST_CLIENT_SECRET")
      token_url     = "https://auth.services.ahara.io/oauth2/token"
      scopes        = ["observability/ingest"]
    }
  }
}

loki.write "default" {
  endpoint {
    url                 = "${loki_push_url}"
    batch_wait          = "1s"
    batch_size          = "1MiB"
    remote_timeout      = "5s"
    min_backoff_period  = "500ms"
    max_backoff_period  = "30s"
    max_backoff_retries = 10
    name                = "loki"

    // Cognito M2M (client_credentials) auth for the TrueNAS ingest gateway.
    // client_id/secret are fetched from SSM at boot into the Alloy env file.
    oauth2 {
      client_id     = sys.env("OBS_INGEST_CLIENT_ID")
      client_secret = sys.env("OBS_INGEST_CLIENT_SECRET")
      token_url     = "https://auth.services.ahara.io/oauth2/token"
      scopes        = ["observability/ingest"]
    }
  }
}

%{ if loki_gateway_enabled ~}
loki.source.api "ec2" {
  http {
    listen_address = "0.0.0.0"
    listen_port    = ${loki_gateway_port}
  }

  labels = {
    gateway = "reverse-proxy",
  }

  forward_to              = [loki.write.default.receiver]
  use_incoming_timestamp = true
}

%{ endif ~}
%{ for idx, log in file_logs ~}
loki.source.file "file_${idx}" {
  targets = [
    {
      __path__  = "${log.file_path}",
      job       = "ahara-ec2",
      source    = "${log.source}",
      host_role = "${host_role}",
    },
  ]
  forward_to    = [loki.write.default.receiver]
  tail_from_end = false

  file_match {
    enabled     = true
    sync_period = "10s"
  }
}

%{ endfor ~}
%{ for idx, log in journal_logs ~}
loki.source.journal "journal_${idx}" {
  forward_to     = [loki.write.default.receiver]
  format_as_json = true
  matches        = "${log.match_expr}"
  max_age        = "1h"
  labels = {
    job       = "ahara-ec2",
    source    = "${log.source}",
    host_role = "${host_role}",
  }
}

%{ endfor ~}
%{ if otlp_gateway_enabled ~}
// ingest-auth: OAuth2 (Cognito M2M) enabled on TrueNAS exporters (rev 1).
otelcol.receiver.otlp "lambda" {
  grpc {
    endpoint = "0.0.0.0:${truenas_otlp_grpc_port}"
  }

  http {
    endpoint = "0.0.0.0:${truenas_otlp_http_port}"
  }

  output {
    metrics = [otelcol.processor.memory_limiter.lambda.input]
    logs    = [otelcol.processor.memory_limiter.lambda.input]
    traces  = [otelcol.processor.memory_limiter.lambda.input]
  }
}

otelcol.processor.memory_limiter "lambda" {
  check_interval = "1s"
  limit          = "96MiB"
  spike_limit    = "24MiB"

  output {
    metrics = [otelcol.processor.batch.lambda.input]
    logs    = [otelcol.processor.batch.lambda.input]
    traces  = [otelcol.processor.batch.lambda.input]
  }
}

otelcol.processor.batch "lambda" {
  timeout             = "5s"
  send_batch_size     = 8192
  send_batch_max_size = 16384

  output {
    metrics = [otelcol.exporter.prometheus.victoriametrics.input]
    logs    = [otelcol.exporter.loki.truenas.input]
    traces  = [otelcol.exporter.otlp.tempo.input]
  }
}

otelcol.exporter.prometheus "victoriametrics" {
  forward_to = [prometheus.remote_write.victoriametrics.receiver]
}

// prometheus.remote_write "victoriametrics" is now declared unconditionally
// near the top of this file (shared with the host-metrics scrape below), so
// it is not redefined here.

// Self-observability: scrape this gateway collector's own /metrics endpoint
// (otelcol_* receiver/exporter/queue metrics) and ship them to TrueNAS
// VictoriaMetrics, so the edge gateway collector appears alongside the local
// TrueNAS Alloy router on the Grafana "Pipeline Health" dashboard. The
// instance label distinguishes the two collectors. The listen address mirrors
// CUSTOM_ARGS (--server.http.listen-addr) set in the host user-data.
prometheus.scrape "alloy_self" {
  targets = [
    {
      __address__ = "127.0.0.1:12345",
      job         = "alloy",
      instance    = "reverse-proxy-gateway",
      host_role   = "${host_role}",
    },
  ]
  forward_to      = [prometheus.remote_write.victoriametrics.receiver]
  scrape_interval = "30s"
}

otelcol.exporter.loki "truenas" {
  forward_to = [loki.write.default.receiver]
}

otelcol.auth.oauth2 "ingest" {
  client_id     = sys.env("OBS_INGEST_CLIENT_ID")
  client_secret = sys.env("OBS_INGEST_CLIENT_SECRET")
  token_url     = "https://auth.services.ahara.io/oauth2/token"
  scopes        = ["observability/ingest"]
}

otelcol.exporter.otlp "tempo" {
  timeout = "5s"

  client {
    endpoint = "${truenas_observability_host}:${truenas_otlp_grpc_port}"
    auth     = otelcol.auth.oauth2.ingest.handler

    tls {
      insecure = true
    }
  }

  retry_on_failure {
    enabled          = true
    initial_interval = "1s"
    max_interval     = "30s"
    max_elapsed_time = "5m"
  }

  sending_queue {
    enabled           = true
    num_consumers     = 4
    queue_size        = 2000
    block_on_overflow = false
  }
}
%{ endif ~}

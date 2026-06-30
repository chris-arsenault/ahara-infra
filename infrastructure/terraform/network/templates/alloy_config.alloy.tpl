logging {
  level  = "info"
  format = "logfmt"
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

prometheus.remote_write "victoriametrics" {
  endpoint {
    url = "http://${truenas_observability_host}:${truenas_victoriametrics_port}/api/v1/write"
  }
}

otelcol.exporter.loki "truenas" {
  forward_to = [loki.write.default.receiver]
}

otelcol.exporter.otlp "tempo" {
  timeout = "5s"

  client {
    endpoint = "${truenas_observability_host}:${truenas_otlp_grpc_port}"

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

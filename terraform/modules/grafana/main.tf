output "alloy_config" {
  value = <<-EOT
    otelcol.receiver.otlp "default" {
      grpc { endpoint = "0.0.0.0:4317" }
      http { endpoint = "0.0.0.0:4318" }
      output {
        metrics = [otelcol.exporter.otlphttp.grafana.input]
        logs    = [otelcol.exporter.otlphttp.grafana.input]
        traces  = [otelcol.exporter.otlphttp.grafana.input]
      }
    }

    otelcol.auth.basic "grafana" {
      username = env("GRAFANA_CLOUD_INSTANCE_ID")
      password = env("GRAFANA_CLOUD_API_TOKEN")
    }

    otelcol.exporter.otlphttp "grafana" {
      client {
        endpoint = env("GRAFANA_CLOUD_OTLP_ENDPOINT")
        auth     = otelcol.auth.basic.grafana.handler
      }
    }
  EOT
}

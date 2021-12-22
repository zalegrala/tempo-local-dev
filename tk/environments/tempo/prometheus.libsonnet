local prometheus = import 'prometheus/prometheus.libsonnet';

prometheus {
  _config+:: {
    prometheus_external_hostname: 'http://prometheus',
    prometheus_enabled_features+: ['remote-write-receiver'],
  },

  prometheus_config+:: {
    scrape_configs: [
      {
        job_name: 'metrics-generator',
        scrape_interval: '15s',
        metrics_path: '/api/trace-metrics',
        kubernetes_sd_configs: [{
          role: 'pod',
        }],
        relabel_configs: [
          // Only keep pods with the label app=metrics-generator
          {
            source_labels: ['__meta_kubernetes_pod_label_app'],
            action: 'keep',
            regex: 'metrics-generator',
          },
        ],
      },
    ],
  },
}

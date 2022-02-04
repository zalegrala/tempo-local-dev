{
  // minimize resources so we can pack more components on this poor laptop
  local resources_small = {
    requests: {
      cpu: '100m',
      memory: '100Mi',
    },
    limits: {
      cpu: '2',
      memory: '2Gi',
    },
  },

  _config+:: {
    metrics_generator+: {
      replicas: 1,
      resources: resources_small,
    },
  },

  tempo_distributor_config+: {
    distributor+: {
      enable_metrics_generator_ring: true,
    },
  },

  tempo_metrics_generator_config+: {
    metrics_generator+: {
      remote_write+: {
        enabled: true,
        client+: {
          url: 'http://prometheus:9090/prometheus/api/v1/write',
        },
      },
    },
  },
}

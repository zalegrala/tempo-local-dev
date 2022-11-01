{
  local k = import 'ksonnet-util/kausal.libsonnet',
  local configMap = k.core.v1.configMap,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,
  local volumeMount = k.core.v1.volumeMount,
  local pvc = k.core.v1.persistentVolumeClaim,
  local statefulset = k.apps.v1.statefulSet,
  local volume = k.core.v1.volume,
  local service = k.core.v1.service,
  local servicePort = service.mixin.spec.portsType,
  local deployment = k.apps.v1.deployment,

  local target_name = 'scalable-single-binary',
  local tempo_config_volume = 'tempo-conf',
  local tempo_query_config_volume = 'tempo-query-conf',
  local tempo_data_volume = 'tempo-data',

  local appName = 'tempo',
  local headlessServiceName = '%s-discovery' % appName,

  withPvc(size, storage_class='local-path'): {
    tempo_pvc:
      pvc.new()
      + pvc.mixin.spec.resources.withRequests({ storage: size })
      + pvc.mixin.spec.withAccessModes(['ReadWriteOnce'])
      + pvc.mixin.spec.withStorageClassName(storage_class)
      + pvc.mixin.metadata.withLabels({ app: appName })
      + pvc.mixin.metadata.withNamespace(self.tempo_ssb.namespace)
      + pvc.mixin.metadata.withName(tempo_data_volume)
      + { kind: 'PersistentVolumeClaim', apiVersion: 'v1' },
  },

  withResources(resources): {
    tempo_container+:
      k.util.resourcesRequests(resources.requests.cpu, resources.requests.memory) +
      k.util.resourcesLimits(resources.limits.cpu, resources.limits.memory),
  },

  withReceivers(receivers): {
    tempo_config+:: {
      distributor+: {
        receivers: receivers,
      },
    },
  },

  withBackend(backend, backend_config): {
    tempo_config+:: {
      storage+: {
        trace+: {
          backend: backend,
          [backend]: backend_config,
        },
      },
    },
  },

  withImage(name, image): {
    tempo_ssb+: {
      images+: {
        [name]: image,
      },
    },
  },

  withInet6(): {
    tempo_service+:
      service.mixin.spec.withIpFamilies(['IPv6'])
      + service.mixin.spec.withIpFamilyPolicy('SingleStack'),

    tempo_config+: {
      server+: {
        http_listen_address: '[::0]',
        grpc_listen_address: '[::0]',
      },
      ingester+: {
        lifecycler+: {
          prefer_inet6: true,
          address: '[::0]',
        },
      },
      memberlist+: {
        // bind_addr: ['[::0]', '0.0.0.0'],
        bind_addr: ['[::0]'],
        bind_port: 7946,
      },
      // query_frontend+: {
      //   prefer_inet6: true,
      // },
      compactor+: {
        ring+: {
          prefer_inet6: true,
        },
      },
      metrics_generator+: {
        ring+: {
          prefer_inet6: true,
        },
      },
    },
  },

  withImagePullPolicy(policy): {
    tempo_container+:
      container.withImagePullPolicy('Always'),
  },

  new(namespace='default', tld='cluster.local'): {
    local ssb = self,

    tempo_ssb:: {
      namespace: namespace,
      tld: tld,
      http_listen_port: 3200,
      grpc_listen_port: 9095,
      replicas: 3,
      resources: {
        requests: {
          cpu: '500m',
          memory: '1Gi',
        },
        limits: {
          cpu: '1',
          memory: '2Gi',
        },
      },
      images:: {
        tempo: 'grafana/tempo:latest',
        tempo_vulture: 'grafana/tempo-vulture:latest',
      },
    },

    tempo_config:: {
      target: 'scalable-single-binary',
      server: {
        log_level: 'debug',
        http_listen_port: ssb.tempo_ssb.http_listen_port,
        grpc_listen_port: ssb.tempo_ssb.grpc_listen_port,
      },

      usage_report: {
        reporting_enabled: true,
      },

      search_enabled: true,
      metrics_generator_enabled: true,
      // use_otel_tracer: true,

      memberlist+: {
        join_members: [
          '%s.%s.svc.%s:7946' % [headlessServiceName, namespace, tld],
        ],
      },

      distributor: {
        log_received_spans: {
          enabled: true,
        },
      },

      ingester: {
        complete_block_timeout: '1m',
        lifecycler+: {
          ring+: {
            replication_factor: 3,
          },
        },
      },
      compactor: {
        compaction: {
          block_retention: '900h',
          compacted_block_retention: '8h',
        },
        ring+: {
          kvstore+: {
            store: 'memberlist',
          },
        },
      },
      querier: {
        frontend_worker: {
          frontend_address: '%s.%s.svc.%s:%s' % [headlessServiceName, namespace, tld, ssb.tempo_ssb.grpc_listen_port],
        },
      },
      storage: {
        trace: {
          block: {
            version: 'vParquet',
          },
          blocklist_poll: '0',
          wal: {
            path: '/var/tempo/wal',
          },
          pool: {
            queue_depth: 2000,
          },
        },
      },
      metrics_generator+: {
        processor+: {
          service_graphs+: {
            dimensions: ['cluster', 'namespace'],
          },
          span_metrics+: {
            dimensions: ['cluster', 'namespace'],
          },
        },
        storage+: {
          path: '/var/tempo/wal',
          remote_write+: [
            {
              url: 'http://prometheus.obs.svc.cluster.znet:9090/api/v1/write',
              send_exemplars: true,
            },
          ],
        },
      },
    },

    namespace:
      k.core.v1.namespace.new(namespace),

    tempo_configmap:
      configMap.new('tempo') +
      configMap.withData({
        'tempo.yaml': k.util.manifestYaml(ssb.tempo_config),
      }) +
      configMap.withDataMixin({
        'overrides.yaml': |||
          overrides:
        |||,
      }),

    tempo_container::
      container.new('tempo', ssb.tempo_ssb.images.tempo)
      + container.withPorts([
        containerPort.new('http-metrics', ssb.tempo_ssb.http_listen_port),
        containerPort.new('grpc', ssb.tempo_ssb.grpc_listen_port),
        containerPort.new('otlp', 4317),
        containerPort.new('jaeger-grpc', 14250),
      ])
      + container.withArgs([
        '-config.file=/conf/tempo.yaml',
      ])
      + container.withVolumeMounts([
        volumeMount.new(tempo_config_volume, '/conf'),
        volumeMount.new(tempo_data_volume, '/var/tempo'),
      ])
      + container.mixin.readinessProbe.httpGet.withPath('/ready')
      + container.mixin.readinessProbe.httpGet.withPort(ssb.tempo_ssb.http_listen_port)
      + container.mixin.readinessProbe.withInitialDelaySeconds(15)
      + container.mixin.readinessProbe.withTimeoutSeconds(1),

    tempo_statefulset:
      statefulset.new('tempo',
                      self.tempo_ssb.replicas,
                      [
                        self.tempo_container,
                      ],
                      self.tempo_pvc,
                      { app: appName }) +
      statefulset.mixin.spec.withServiceName(appName) +
      statefulset.mixin.spec.template.metadata.withAnnotations({
        config_hash: std.md5(std.toString(ssb.tempo_configmap.data['tempo.yaml'])),
      }) +
      statefulset.mixin.spec.template.spec.withVolumes([
        volume.fromConfigMap(tempo_config_volume, ssb.tempo_configmap.metadata.name),
      ]),

    tempo_service:
      k.util.serviceFor(self.tempo_statefulset),

    tempo_headless_service:
      k.util.serviceFor(self.tempo_statefulset)
      + service.metadata.withName(headlessServiceName)
      + service.mixin.spec.withClusterIP('None')
      + service.mixin.spec.withPublishNotReadyAddresses(true),
  },
}

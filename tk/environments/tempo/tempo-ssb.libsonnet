local k = import 'ksonnet-util/kausal.libsonnet';
local container = k.core.v1.container;

local minio = import 'minio/minio.libsonnet';
local tempo_ssb = import 'tempo-ssb/tempo.libsonnet';
local minio = import 'minio/minio.libsonnet';
local vulture = import 'microservices/vulture.libsonnet';

minio
+ tempo_ssb.new()
+ tempo_ssb.withPvc('1Gi', 'local-path')
+ tempo_ssb.withResources({
  requests: {
    cpu: '500m',
    memory: '1Gi',
  },
  limits: {
    cpu: '1',
    memory: '2Gi',
  },
})
+ tempo_ssb.withReceivers({
  otlp: {
    protocols: {
      grpc: null,
    },
  },
  jaeger: {
    protocols: {
      // traces from vulture
      grpc: null,
    },
  },
})
+ tempo_ssb.withBackend('s3', {
  bucket: 'tempo',
  endpoint: 'minio:9000',
  access_key: 'tempo',
  secret_key: 'supersecret',
  insecure: true,
})
// + tempo_ssb.withImage('tempo', 'zalegrala/tempo:inet6-dirty')
+ tempo_ssb.withImage('tempo', 'grafana/tempo:latest')
// + tempo_ssb.withInet6()
+ tempo_ssb.withImagePullPolicy('Always')

+ {
  local jaeger_tracing = container.withEnvMixin([
    container.envType.new('JAEGER_ENDPOINT', 'http://tempo.trace.svc.cluster.znet:14268/api/traces'),
    container.envType.new('JAEGER_TAGS', 'namespace=%s,cluster=%s' % [$._config.namespace, $._config.cluster]),
    container.envType.new('JAEGER_SAMPLER_TYPE', 'const'),
    container.envType.new('JAEGER_SAMPLER_PARAM', '1'),
  ]),

  tempo_container+::
    jaeger_tracing,
}
+ vulture
+ {
  _images+:: {
    tempo_vulture: 'grafana/tempo-vulture:latest',
  },
  _config+:: {
    vulture: {
      replicas: 0,
      tempoPushUrl: 'http://tempo',
      tempoQueryUrl: 'http://tempo:3200',
      tempoOrgId: '',
      tempoRetentionDuration: '336h',
      tempoSearchBackoffDuration: '5s',
      tempoReadBackoffDuration: '10s',
      tempoWriteBackoffDuration: '10s',
    },
  },
}

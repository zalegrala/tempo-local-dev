local k = import 'k.libsonnet';
local kausal = import 'ksonnet-util/kausal.libsonnet';
local configMap = k.core.v1.configMap;
local grafana = import 'grafana/grafana.libsonnet';

{
  local this = self,

  grafana:
    grafana +
    // grafana.withAnonymous() +
    grafana.withTheme('dark') +
    grafana.withRootUrl('http://localhost:3000') +
    grafana.withImage('grafana/grafana-enterprise:latest') +
    grafana.withEnterpriseLicenseText((importstr '/home/zach/go/src/github.com/grafana/backend-enterprise/development/fixtures/grafana-license.jwt')) +
    grafana.addPlugin('grafana-enterprise-traces-app') +

    grafana.withGrafanaIniConfig({
      sections+: {
        feature_toggles: {
          enable: 'tempoSearch,tempoServiceGraph,tempoApmTable,traceqlEditor',
        },
      },
    }) +
    {
      pluginsConfigMap:
        configMap.new('grafana-plugins', {
          'instance-mgmt.yml': kausal.util.manifestYaml({
            apiVersion: 1,
            apps: [
              {
                type: 'grafana-enterprise-traces-app',
                jsonData: {
                  backendUrl: 'http://tempo-enterprise-gateway.tempo-test.svc.cluster.znet:3100',
                  base64EncodedAccessTokenSet: true,
                },
                secureJsonData: {
                  base64EncodedAccessToken: 'X19hZG1pbl9fLWM3ZDZmYTdjZTdlMDlhNTM6NiU1MDEwXz15MCgqIkslInswMjdhIjJu',
                },
              },
            ],
          }),
        }),

      grafana_deployment+:
        kausal.util.configMapVolumeMount(self.pluginsConfigMap, self._config.provisioningDir + '/plugins'),
    },

}

"""Maintainer-side: chart .tgz pin for the helm-template render.

Consumers don't see this — it's loaded only by the dev-only chart-fetch
extension under tools/. The committed manifest at
`//private/manifests:grafana.yaml` is what consumers actually consume.
"""

GRAFANA_CHART_VERSIONS = {
    "10.5.15": {
        "chart_url":    "https://github.com/grafana/helm-charts/releases/download/grafana-10.5.15/grafana-10.5.15.tgz",
        "chart_sha256": "c08c87969270402e7d5227edb8385af67cc32ee34817bff89773ad02303b5d79",
    },
}

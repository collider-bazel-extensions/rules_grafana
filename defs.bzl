"""Public API for rules_grafana.

Two macros that wrap rules_kubectl's `kubectl_apply` /
`kubectl_apply_health_check` with Grafana-specific defaults: the
namespace, the committed pre-rendered manifest, and the right wait
shape (the chart's `grafana` Deployment).

Same shape as rules_loki — pure glue. No per-rule launcher, no toolchain.
"""

load("@rules_kubectl//:defs.bzl", "kubectl_apply", "kubectl_apply_health_check")

# Deployment name in the rendered manifest. The chart names it after the
# release name, which we pin to `grafana` at maintainer-render time.
_GRAFANA_DEPLOY = "grafana"

def grafana_install(
        name,
        namespace = "grafana",
        wait_timeout = "300s",
        **kwargs):
    """Apply the pinned Grafana manifest into `namespace` and block until
    the Deployment is Available before idling.

    Drops into `itest_service.exe`.

    Args:
      name: target name.
      namespace: target namespace. Pre-created idempotently. Default
        `grafana`. The rendered manifest is namespace-agnostic; you can
        change this freely.
      wait_timeout: timeout for the `kubectl wait deploy --for=condition=Available`.
      **kwargs: forwarded to `kubectl_apply` (e.g. `tags`, `kubeconfig_env`,
        extra `wait_for_*` lists).
    """
    extra_deps = kwargs.pop("wait_for_deployments", [])
    kubectl_apply(
        name = name,
        manifests = ["@rules_grafana//private/manifests:grafana.yaml"],
        namespace = namespace,
        create_namespace = True,
        server_side = True,
        wait_for_deployments = [_GRAFANA_DEPLOY] + list(extra_deps),
        wait_timeout = wait_timeout,
        **kwargs
    )

def grafana_health_check(
        name,
        namespace = "grafana",
        **kwargs):
    """Readiness probe paired with `grafana_install`.

    Drops into `itest_service.health_check`.
    """
    extra_deps = kwargs.pop("wait_for_deployments", [])
    kubectl_apply_health_check(
        name = name,
        namespace = namespace,
        wait_for_deployments = [_GRAFANA_DEPLOY] + list(extra_deps),
        **kwargs
    )

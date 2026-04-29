# rules_grafana

Hermetic [Grafana](https://grafana.com/oss/grafana/) install for Bazel
test compositions. Pure glue layer over
[`rules_kubectl`](https://github.com/collider-bazel-extensions/rules_kubectl) —
`grafana_install` is a macro that emits a `kubectl_apply` target
pre-configured with Grafana's pinned manifest, namespace, and
Deployment-Available wait.

```python
load("@rules_grafana//:defs.bzl", "grafana_install", "grafana_health_check")

grafana_install(name = "grafana_install_bin")
grafana_health_check(name = "grafana_health_bin")
```

That's the whole API. Drop into `rules_itest` like any other operator
install — see [the smoke test](tests/) for the canonical composition.

**Pinned versions:** Grafana helm chart 10.5.15 (Grafana appVersion
12.3.1). Rendered with anonymous-Admin auth, no plugins, sqlite in
emptyDir, no telemetry — a **smoke fixture**, NOT a production starting
point. Consumers writing real deployments should override most of the
values. The values file used at render time is exported as
`@rules_grafana//config:grafana-values.yaml` for inspection / extension.

**Supported platforms (v0.1):** any platform where `bash + python3 + kubectl`
runs (the rules_kubectl substrate). Validated on Linux x86\_64 in CI.

---

## Contents

- [Installation](#installation) (Bzlmod-only)
- [Quickstart](#quickstart)
- [Composition with rules_itest](#composition-with-rules_itest)
- [Macros](#macros)
- [Production note](#production-note)
- [Hermeticity exceptions](#hermeticity-exceptions)
- [Contributing](#contributing)

---

## Installation

```python
bazel_dep(name = "rules_grafana", version = "0.1.0")
```

Bzlmod-only. `rules_grafana` transitively pulls in
[`rules_kubectl`](https://github.com/collider-bazel-extensions/rules_kubectl).
Until BCR, consume via `archive_override` or a git pin.

---

## Quickstart

```python
load("@rules_itest//:itest.bzl", "itest_service", "service_test")
load("@rules_kind//:defs.bzl", "kind_cluster", "kind_health_check")
load("@rules_grafana//:defs.bzl", "grafana_install", "grafana_health_check")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")

# 1. Cluster.
kind_cluster(name = "cluster", k8s_version = "1.32")
kind_health_check(name = "cluster_health", cluster = ":cluster")
itest_service(name = "kind_svc", exe = ":cluster", health_check = ":cluster_health")

# 2. Grafana — applies the pinned manifest, waits for the Deployment Available.
grafana_install(name = "grafana_install_bin")
grafana_health_check(name = "grafana_health_bin")

# 3. Wrappers (source the kind env file so KUBECONFIG/KUBECTL cross
#    `exec`).
sh_binary(name = "grafana_install_wrapper", srcs = ["install_wrapper.sh"], data = [":grafana_install_bin"])
sh_binary(name = "grafana_health_wrapper",  srcs = ["health_wrapper.sh"],  data = [":grafana_health_bin"])

itest_service(
    name = "grafana_svc",
    exe = ":grafana_install_wrapper",
    deps = [":kind_svc"],
    health_check = ":grafana_health_wrapper",
)
```

---

## Composition with rules_itest

Stack `grafana_svc` underneath any service that needs Grafana to exist —
identical shape to every other in-cluster operator rule in this family.
The in-tree smoke test does:

```
kind_svc → grafana_svc → curl-pod assertion test
```

…where the curl pod POSTs a `testdata` datasource and GETs it back.

---

## Macros

### `grafana_install(name, namespace = "grafana", wait_timeout = "300s", **kwargs)`

Expands to a `kubectl_apply(...)` target that:

- Applies `@rules_grafana//private/manifests:grafana.yaml`.
- `create_namespace = True` for `namespace` (default `grafana`).
- `server_side = True`.
- `wait_for_deployments = ["grafana"]` (the chart's single Deployment).
- Forwards everything else.

Drops into `itest_service.exe`.

### `grafana_health_check(name, namespace = "grafana", **kwargs)`

Expands to a `kubectl_apply_health_check(...)` target with the matching
wait shape. Drops into `itest_service.health_check`.

---

## Production note

**The shipped values file is a smoke fixture.** It enables:

- `auth.anonymous.enabled: true` with `org_role: Admin` — anyone reachable to the Service has full admin access. Done so the in-tree smoke can POST datasources without recovering the admin password.
- `persistence.enabled: false` — sqlite in emptyDir. **Lost on pod restart.**
- `analytics.reporting_enabled: false`, `check_for_updates: false` — no telemetry / network reach.
- `plugins: []` — no plugin pre-fetch.

For a production deployment, copy `config/grafana-values.yaml` into your
own repo, harden every `auth.*` field, switch to a real PVC, decide
which plugins / dashboards / datasources to provision via the chart, and
re-render with your own pipeline (or use `rules_helm`'s `helm_template`
directly).

---

## Hermeticity exceptions

| Component | Status | Notes |
|---|---|---|
| Grafana manifest | Fully hermetic. Pre-rendered by `tools/render_grafana.sh` from the upstream chart .tgz, sha-pinned in `tools/versions.bzl`. | Re-render with `bash tools/render_grafana.sh <ver>`. |
| `kubectl` | **Not vendored** — inherited from `rules_kubectl`. | |
| Target cluster | Out of scope — bring your own. | |
| Grafana container image | Pulled at runtime by the cluster's nodes. | Future: `kind_cluster.images` if needed. |
| Smoke-test curl image | `curlimages/curl` pulled at smoke time. | `requires-network`-tagged. |

---

## Contributing

PRs welcome. Conventions match the sibling rule sets:

- New rules need an analysis test in `tests/analysis_tests.bzl`.
- Bumping the pinned chart version: edit `tools/versions.bzl`, add the new `helm_template + sh_binary` block in `tools/BUILD.bazel`, run `bash tools/render_grafana.sh <new-version>`, commit.
- `MODULE.bazel.lock` is intentionally not committed.

### Help wanted: macOS validation

The macros are platform-independent. A pasted log from a green
`bazel test //tests:smoke_test` on macOS would unblock the macOS support
claim.

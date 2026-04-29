# rules_grafana — design decisions

Hermetic [Grafana](https://grafana.com/oss/grafana/) install for Bazel
test compositions. Pure glue over
[`rules_kubectl`](https://github.com/collider-bazel-extensions/rules_kubectl)
and (at maintainer time)
[`rules_helm`](https://github.com/collider-bazel-extensions/rules_helm).

Same shape as [`rules_loki`](https://github.com/collider-bazel-extensions/rules_loki) —
the second rule set in the family that's pure glue, no per-rule
launcher / toolchain. `grafana_install` and `grafana_health_check` are
macros that emit `kubectl_apply` / `kubectl_apply_health_check` targets
pre-configured for Grafana. ~50 lines of Starlark + a committed
pre-rendered manifest.

## Decided

| # | Decision | Choice | Source |
|---|---|---|---|
| 1 | Bzlmod / WORKSPACE | **Bzlmod-only at v0.1.** | Sibling-family precedent |
| 2 | Architecture | **Layered.** Two macros wrapping `kubectl_apply` / `kubectl_apply_health_check`. No per-rule launcher.py, no toolchain, no extension at the public layer. | rules_loki precedent |
| 3 | Manifest provisioning | Grafana helm chart **pre-rendered** into `private/manifests/grafana.yaml` via `rules_helm`'s `helm_template` + a write-back target under `tools/`. Committed. Consumers don't need helm. | rules_loki / rules_capsule / rules_cilium pattern |
| 4 | Render mode | **Minimal smoke footprint.** 1 replica, sqlite in emptyDir (no PVC), no plugins, anonymous auth ENABLED with Admin role. The smoke must not need to recover the admin password or set up a real storage class. | Grafana-specific |
| 5 | Public surface | `grafana_install`, `grafana_health_check`. **No `GrafanaInfo` provider** in v0.1 — nothing introspects it yet. | Layered architecture |
| 6 | Namespace | `grafana` (default). Macros pass `create_namespace = True`; the chart's manifest is namespace-agnostic so consumers can change it freely. | rules_kubectl-driven |
| 7 | Wait shape | `wait_for_deployments = ["grafana"]` (the single replica from the chart). | Grafana-specific |
| 8 | Anonymous-Admin auth in smoke values | Smoke test must POST to `/api/datasources` without resolving the admin Secret. The chart ships an admin password as a generated Secret; recovering it would require a `kubectl get secret` extra step. Anonymous-Admin sidesteps that — acceptable for a sealed kind cluster used for one round-trip assertion. | Smoke pragmatic |
| 9 | Disabled chart features | `analytics.reporting_enabled: false`, `check_for_updates: false`, `check_for_plugin_updates: false` — Grafana otherwise reaches out to grafana.com on startup, slowing the test and adding a network dependency. `testFramework.enabled: false` removes the chart-internal `helm test` artifacts (we have our own). `persistence.enabled: false` keeps storage in emptyDir. | Smoke pragmatic |
| 10 | rules_kubectl dependency | **Public dep** (the macros expand to its rules in consumer code). | Architectural choice |
| 11 | rules_helm dependency | **Dev-only.** Maintainer-side render only. | rules_loki precedent |
| 12 | Smoke assertion | **POST + GET round-trip a `testdata` datasource** through `/api/datasources` and `/api/datasources/name/<name>`. Proves Grafana's API and sqlite persistence work end-to-end. Memory entry "smoke tests must exercise the functionality" is the durable rule. `testdata` is a built-in datasource type — no upstream system required. | Smoke pragmatic |
| 13 | Naming | snake_case rules/macros, `MixedCaseInfo` providers (none in v0.1), `UPPER_SNAKE` constants. | All siblings |
| 14 | Update workflow | `bash tools/render_grafana.sh <chart-version>` → thin shim around `bazel run //tools:render_writeback_<dotted_version>`. Hermetic (rules_helm's helm); no host helm needed. | rules_loki precedent |

## Grafana-specific notes

- The chart names the Deployment after the release name. We pin the release name to `grafana` at maintainer-render time so the macros' `wait_for_deployments = ["grafana"]` matches.
- Anonymous-Admin auth is **dangerous in production**. The values file is shipped as a *test fixture*; consumers writing real production deployments should override every `grafana.ini.auth.*` field.
- The `testdata` datasource type (built into Grafana since 8.x) generates fake metrics on demand. Used here for the round-trip smoke because it requires zero upstream — no Prometheus, no Loki, no DB.

## v0.1.0 status (planning)

| Area | State |
|---|---|
| MODULE.bazel (Bzlmod-only) | planned |
| `grafana_install` + `grafana_health_check` macros | planned |
| Pinned Grafana helm chart 10.5.15 (rendered + committed) | planned |
| `config/grafana-values.yaml` (exported) | planned |
| Maintainer render flow | planned |
| Analysis test | planned |
| In-tree smoke (kind + Grafana + datasource POST/GET round-trip) | planned |
| End-to-end `bazel test` runtime | planned (validated under CI Docker; macOS pending) |

## Deferred (not v0.1.0)

- **`GrafanaInfo` provider** — for downstream introspection. Add when a consumer asks.
- **Production-shaped values** — auth hardening, real persistence, ServiceMonitor, dashboards. v0.1 is a smoke fixture.
- **Provisioning datasources / dashboards via the chart's `datasources:` / `dashboards:` keys** — requires a separate render variant. Add when there's a real consumer pattern.
- **Companion rule pulling Loki + Grafana together** — would compose `rules_loki` + `rules_grafana` + a provisioned Loki datasource. The piece worth building once a consumer asks.

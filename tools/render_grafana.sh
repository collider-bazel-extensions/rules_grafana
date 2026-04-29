#!/usr/bin/env bash
# tools/render_grafana.sh — thin shim around the Bazel-native render flow.
#
# Maintainer flow:
#   1. Edit tools/versions.bzl::GRAFANA_CHART_VERSIONS to add/change the
#      entry, including chart_url + chart_sha256. Compute the chart sha:
#          curl -fsSL "<url>" | sha256sum
#   2. Add (or update) a `helm_template` + `sh_binary` block in
#      tools/BUILD.bazel for the new version.
#   3. Run this script:
#          bash tools/render_grafana.sh <chart-version>
#
# Host helm is NOT required — the helm binary comes from rules_helm.
set -euo pipefail

VERSION="${1:?usage: tools/render_grafana.sh <chart-version>}"
TARGET="//tools:render_writeback_$(echo "$VERSION" | tr '.' '_')"

echo "[render_grafana] $TARGET"
exec bazel run "$TARGET"

#!/usr/bin/env bash
# Round-trips a Grafana datasource via the HTTP API to prove Grafana's
# API + sqlite persistence both work end-to-end. Strategy:
#
#   1. `kubectl run` a curl pod inside the cluster.
#   2. From that pod, POST a `testdata` datasource to Grafana's
#      /api/datasources. (The `testdata` datasource type is built into
#      Grafana — no upstream system required.)
#   3. From the same pod, GET it back via /api/datasources/name/<name>
#      and assert the returned JSON contains the values we pushed.
#
# Anonymous-Admin auth is on (config/grafana-values.yaml) so we don't
# need to recover the admin password.
set -euo pipefail

CLUSTER_NAME="cluster"
env_file="$TEST_TMPDIR/${CLUSTER_NAME}.env"
[[ -f "$env_file" ]] || { echo "missing kind env file" >&2; exit 1; }
# shellcheck disable=SC1090
source "$env_file"

KCTL=("$KUBECTL" --kubeconfig="$KUBECONFIG")

GRAFANA_HOST="grafana.grafana.svc.cluster.local"
DS_NAME="rules_grafana_smoke_$RANDOM"
NS="${GRAFANA_SMOKE_NS:-default}"

echo "smoke_test: launching curl pod"
"${KCTL[@]}" -n "$NS" run grafana-curl --restart=Never --image=curlimages/curl:8.10.1 \
    --command -- sleep 600
trap '"${KCTL[@]}" -n "$NS" delete pod grafana-curl --ignore-not-found --wait=false >/dev/null 2>&1 || true' EXIT
"${KCTL[@]}" -n "$NS" wait pod/grafana-curl --for=condition=Ready --timeout=60s

# Wait until /api/health says the database is OK. grafana-install already
# blocks on the Deployment Available, but the HTTP server warms up a
# moment after that.
echo "smoke_test: waiting for /api/health"
deadline=$(( $(date +%s) + 60 ))
while (( $(date +%s) < deadline )); do
  health=$("${KCTL[@]}" -n "$NS" exec grafana-curl -- \
      curl -s "http://${GRAFANA_HOST}/api/health" 2>/dev/null || true)
  if grep -q '"database": *"ok"' <<<"$health"; then
    break
  fi
  sleep 2
done
if ! grep -q '"database": *"ok"' <<<"$health"; then
  echo "smoke_test: FAIL — /api/health never reported database ok" >&2
  echo "$health" >&2
  exit 1
fi
echo "smoke_test: /api/health -> database: ok"

echo "smoke_test: POST datasource '$DS_NAME' (type=testdata)"
PUSH_BODY=$(cat <<EOF
{"name":"${DS_NAME}","type":"testdata","access":"proxy","isDefault":false}
EOF
)
post_status=$("${KCTL[@]}" -n "$NS" exec grafana-curl -- \
    curl -s -o /dev/null -w "%{http_code}" \
    -X POST -H "Content-Type: application/json" \
    --data-binary "$PUSH_BODY" \
    "http://${GRAFANA_HOST}/api/datasources")
if [[ "$post_status" != "200" ]]; then
  echo "smoke_test: FAIL — POST /api/datasources returned HTTP $post_status (expected 200)" >&2
  exit 1
fi
echo "smoke_test: POST /api/datasources -> 200"

echo "smoke_test: GET /api/datasources/name/$DS_NAME"
get_body=$("${KCTL[@]}" -n "$NS" exec grafana-curl -- \
    curl -s "http://${GRAFANA_HOST}/api/datasources/name/${DS_NAME}")

# Round-trip: name + type both came back.
failed=0
grep -q "\"name\": *\"${DS_NAME}\"" <<<"$get_body" || { echo "smoke_test: missing name" >&2; failed=1; }
grep -q "\"type\": *\"testdata\""    <<<"$get_body" || { echo "smoke_test: missing type" >&2; failed=1; }

if (( failed )); then
  echo "---- response ----" >&2
  echo "$get_body" >&2
  echo "---- grafana logs (tail) ----" >&2
  "${KCTL[@]}" -n grafana logs deploy/grafana --tail=50 >&2 || true
  exit 1
fi

echo "smoke_test: OK — datasource '$DS_NAME' round-tripped through Grafana's API + sqlite"

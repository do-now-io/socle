#!/usr/bin/env bash
# victoria_traces in e2e-aws-catalog, after the job applied the module on or
# off. It is off by default (pre-GA), so the default path proves only that it
# applies nothing; this is where it is proven on:
#   on   the module is Ready on a Bound claim, the gateway exports traces,
#        grafana provisions the Jaeger datasource, and one OTLP span posted by
#        podinfo to the gateway is found by its trace id through the Jaeger API
#   off  the release is gone, and so are the gateway's traces pipeline and
#        grafana's Jaeger datasource
set -euo pipefail
relay() { kubectl -n otel-gateway get configmap otel-gateway -o jsonpath='{.data.relay}' 2>/dev/null || true; }
dsy() { kubectl -n grafana get configmap grafana -o jsonpath='{.data.datasources\.yaml}' 2>/dev/null || true; }

case "${1:-}" in
  on)
    SECONDS=0
    back=false
    for _ in $(seq 1 60); do
      status="$(kubectl -n flux-system get resourceset victoria-traces \
        -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
      if [ "$status" = True ] && [ "$(kubectl -n victoria-traces get pvc victoria-traces \
        -o jsonpath='{.status.phase}' 2>/dev/null || true)" = Bound ]; then
        back=true
        break
      fi
      sleep 5
    done
    [ "$back" = true ] || { echo "::error::victoria-traces never became Ready on a Bound claim"; exit 1; }
    kubectl -n victoria-traces wait deploy/victoria-traces --for=condition=Available --timeout=120s
    echo "victoria-traces on: Ready on a Bound claim after ${SECONDS}s"
    for _ in $(seq 1 36); do relay | grep -q otlp_http/victoria-traces && break; sleep 5; done
    relay | grep -q otlp_http/victoria-traces || { echo "::error::the gateway has no traces exporter"; exit 1; }
    kubectl -n otel-gateway rollout status deployment/otel-gateway --timeout=180s
    for _ in $(seq 1 36); do dsy | grep -q victoria-traces && break; sleep 5; done
    dsy | grep -q 'type: jaeger' || { echo "::error::grafana provisions no Jaeger datasource for victoria-traces"; exit 1; }
    echo "the gateway exports traces, grafana provisions the Jaeger datasource"
    # One span, OTLP/JSON, trace and span ids in hex as the spec writes them,
    # posted by podinfo to the gateway, which forwards it as protobuf.
    now="$(date +%s)"
    trace_id="$(printf '%08x' "$now")$(printf '%024x' 42)"
    payload="$(printf '{"resourceSpans":[{"resource":{"attributes":[{"key":"service.name","value":{"stringValue":"socle-e2e"}}]},"scopeSpans":[{"spans":[{"traceId":"%s","spanId":"%016x","name":"socle-e2e-span","kind":1,"startTimeUnixNano":"%s","endTimeUnixNano":"%s"}]}]}]}' \
      "$trace_id" 7 "$(( (now - 2) * 1000000000 ))" "$(( (now - 1) * 1000000000 ))")"
    kubectl -n hello exec deploy/podinfo -- curl -sSf -H 'Content-Type: application/json' \
      --data-binary "$payload" http://otel-gateway.otel-gateway.svc:4318/v1/traces > /dev/null
    vt=/api/v1/namespaces/victoria-traces/services/victoria-traces:http/proxy/select/jaeger/api
    SECONDS=0
    found=false
    for _ in $(seq 1 36); do
      got="$(kubectl get --raw "$vt/traces/$trace_id" 2>/dev/null \
        | python3 -c 'import sys,json; d=json.load(sys.stdin).get("data") or []; print(d[0]["traceID"] if d else "")' \
        2>/dev/null || true)"
      [ "$got" = "$trace_id" ] && { found=true; break; }
      sleep 5
    done
    [ "$found" = true ] || { echo "::error::a trace posted to the gateway never reached victoria-traces"; exit 1; }
    echo "trace $trace_id posted by hello/podinfo, found through the Jaeger API after ${SECONDS}s"
    echo "jaeger services: $(kubectl get --raw "$vt/services" | python3 -c 'import sys,json; print(" ".join(json.load(sys.stdin).get("data") or []))')"
    kubectl -n victoria-traces top pod --no-headers 2>/dev/null \
      | awk '{print "victoria-traces: " $1 " cpu=" $2 " memory=" $3}' || true
    ;;
  off)
    out=""
    for _ in $(seq 1 36); do
      out="$(kubectl -n victoria-traces get helmrelease victoria-traces 2>&1)" || break
      sleep 5
    done
    case "$out" in
      *NotFound*|*"not found"*) echo "helmrelease victoria-traces/victoria-traces is gone" ;;
      *) echo "::error::victoria-traces' HelmRelease still there: $out"; exit 1 ;;
    esac
    for _ in $(seq 1 36); do relay | grep -q otlp_http/victoria-traces || break; sleep 5; done
    if relay | grep -q otlp_http/victoria-traces; then echo "::error::the gateway kept its traces exporter"; exit 1; fi
    for _ in $(seq 1 36); do dsy | grep -q victoria-traces || break; sleep 5; done
    if dsy | grep -q victoria-traces; then echo "::error::grafana kept the Jaeger datasource"; exit 1; fi
    echo "victoria_traces off again: release gone, no traces pipeline, no Jaeger datasource"
    ;;
  *)
    echo "usage: $0 on|off" >&2
    exit 2
    ;;
esac

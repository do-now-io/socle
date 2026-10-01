# Sourced by the `script` step of chainsaw-test.yaml. post_span: one span,
# OTLP/JSON, trace and span ids in hex as the spec writes them, posted by
# podinfo to the gateway (which forwards it as protobuf); prints the trace id.
post_span() {
  now="$(date +%s)"
  trace_id="$(printf '%08x' "$now")$(printf '%024x' 42)"
  payload="$(printf '{"resourceSpans":[{"resource":{"attributes":[{"key":"service.name","value":{"stringValue":"socle-e2e"}}]},"scopeSpans":[{"spans":[{"traceId":"%s","spanId":"%016x","name":"socle-e2e-probe","kind":1,"startTimeUnixNano":"%s","endTimeUnixNano":"%s"}]}]}]}' \
    "$trace_id" 7 "$(( (now - 2) * 1000000000 ))" "$(( (now - 1) * 1000000000 ))")"
  kubectl -n hello exec deploy/podinfo -- curl -sSf -H 'Content-Type: application/json' \
    --data-binary "$payload" http://otel-gateway.otel-gateway.svc:4318/v1/traces > /dev/null
  echo "$trace_id"
}
# find_trace <trace id>: polls the Jaeger query API, through the API server's
# service proxy, until the trace is there; prints the services it knows.
find_trace() {
  vt=/api/v1/namespaces/victoria-traces/services/victoria-traces:http/proxy/select/jaeger/api
  for _ in $(seq 1 36); do
    got="$(kubectl get --raw "$vt/traces/$1" 2>/dev/null \
      | python3 -c 'import sys,json; d=json.load(sys.stdin).get("data") or []; print(d[0]["traceID"] if d else "")' \
      2>/dev/null || true)"
    [ "$got" = "$1" ] && break
    sleep 5
  done
  [ "$got" = "$1" ] || { echo "a trace posted to the gateway never reached victoria-traces"; return 1; }
  echo "trace $1 posted by hello/podinfo, found through the Jaeger API"
  echo "jaeger services: $(kubectl get --raw "$vt/services" | python3 -c 'import sys,json; print(" ".join(json.load(sys.stdin).get("data") or []))')"
}

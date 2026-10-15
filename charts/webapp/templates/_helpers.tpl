{{/* webapp's own container fields: the port, named http, and the probes. */}}
{{- define "webapp.container" -}}
ports:
  - name: http
    containerPort: {{ .Values.port }}
    protocol: TCP
livenessProbe:
  {{- toYaml .Values.livenessProbe | nindent 2 }}
readinessProbe:
  {{- toYaml .Values.readinessProbe | nindent 2 }}
{{- end -}}

{{/* webapp's own pod fields: the replicas spread across nodes and zones. */}}
{{- define "webapp.pod" -}}
topologySpreadConstraints:
{{- range list "kubernetes.io/hostname" "topology.kubernetes.io/zone" }}
  - maxSkew: 1
    topologyKey: {{ . }}
    whenUnsatisfiable: {{ $.Values.topologySpread.whenUnsatisfiable }}
    labelSelector:
      matchLabels:
        {{- include "socle-lib.selectorLabels" $ | nindent 8 }}
{{- end }}
{{- end -}}

{{/* The labels the pods are selected by: never changed once deployed. */}}
{{- define "socle-lib.selectorLabels" -}}
app.kubernetes.io/name: {{ include "socle-lib.fullname" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/* Every object's labels: the selector's, the chart that rendered it, Helm. */}}
{{- define "socle-lib.labels" -}}
{{ include "socle-lib.selectorLabels" . }}
app.kubernetes.io/component: {{ .Chart.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end -}}

{{/* metadata: name and labels. Takes (dict "root" . "name" "<the object's name>"). */}}
{{- define "socle-lib.metadata" -}}
name: {{ .name }}
labels:
  {{- include "socle-lib.labels" .root | nindent 2 }}
{{- end -}}

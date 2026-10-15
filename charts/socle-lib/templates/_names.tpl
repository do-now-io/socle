{{/*
The workload, its Service, ServiceAccount, HorizontalPodAutoscaler and
PodDisruptionBudget are named after the release; every object the client
lists (a route, a ConfigMap, a disk…) is <release>-<name>.
*/}}
{{- define "socle-lib.fullname" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* <release>-<name>, for an object of a list. Takes (dict "root" . "name" "config"). */}}
{{- define "socle-lib.objectName" -}}
{{- printf "%s-%s" (include "socle-lib.fullname" .root) .name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Fails when two entries of a list share a name: they would render one object
twice, the second overwriting the first. JSON Schema cannot compare the items
of a list. Takes (dict "key" "configMaps" "items" .Values.configMaps).
*/}}
{{- define "socle-lib.uniqueNames" -}}
{{- $seen := dict -}}
{{- range .items -}}
{{- if hasKey $seen .name -}}
{{- fail (printf "%s: two named %s" $.key .name) -}}
{{- end -}}
{{- $_ := set $seen .name true -}}
{{- end -}}
{{- end -}}

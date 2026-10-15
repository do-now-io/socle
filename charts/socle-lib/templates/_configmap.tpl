{{/* One ConfigMap per entry of configMaps, named <release>-<name>. */}}
{{- define "socle-lib.configMaps" -}}
{{- include "socle-lib.uniqueNames" (dict "key" "configMaps" "items" .Values.configMaps) -}}
{{- range .Values.configMaps }}
---
apiVersion: v1
kind: ConfigMap
metadata:
  {{- include "socle-lib.metadata" (dict "root" $ "name" (include "socle-lib.objectName" (dict "root" $ "name" .name))) | nindent 2 }}
data:
  {{- toYaml .data | nindent 2 }}
{{- end }}
{{- end -}}

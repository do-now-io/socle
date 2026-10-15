{{/*
One ExternalSecret per entry of externalSecrets: it writes the Secret
<release>-<name>, the name the chart fixes, from the store the client names.
*/}}
{{- define "socle-lib.externalSecrets" -}}
{{- include "socle-lib.uniqueNames" (dict "key" "externalSecrets" "items" .Values.externalSecrets) -}}
{{- range .Values.externalSecrets }}
{{- $name := include "socle-lib.objectName" (dict "root" $ "name" .name) }}
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  {{- include "socle-lib.metadata" (dict "root" $ "name" $name) | nindent 2 }}
spec:
  secretStoreRef:
    {{- toYaml .secretStoreRef | nindent 4 }}
  target:
    name: {{ $name }}
  data:
    {{- toYaml .data | nindent 4 }}
{{- end }}
{{- end -}}

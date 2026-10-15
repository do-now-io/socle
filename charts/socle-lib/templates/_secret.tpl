{{/*
One Secret per entry of secrets, named <release>-<name>, from values in
plaintext: stringData, which Kubernetes encodes.
*/}}
{{- define "socle-lib.secrets" -}}
{{- include "socle-lib.uniqueNames" (dict "key" "secrets" "items" .Values.secrets) -}}
{{- range .Values.secrets }}
---
apiVersion: v1
kind: Secret
metadata:
  {{- include "socle-lib.metadata" (dict "root" $ "name" (include "socle-lib.objectName" (dict "root" $ "name" .name))) | nindent 2 }}
type: Opaque
stringData:
  {{- toYaml .stringData | nindent 2 }}
{{- end }}
{{- end -}}

{{/* The release's own ServiceAccount, its token not mounted unless asked. */}}
{{- define "socle-lib.serviceAccount" -}}
apiVersion: v1
kind: ServiceAccount
metadata:
  {{- include "socle-lib.metadata" (dict "root" . "name" (include "socle-lib.fullname" .)) | nindent 2 }}
  {{- with .Values.serviceAccount.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
automountServiceAccountToken: {{ .Values.serviceAccount.automountServiceAccountToken }}
{{- end -}}

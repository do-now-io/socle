{{/*
One PersistentVolumeClaim per entry of persistence, named <release>-<name>.
Kept by default when the release or the Application goes: Helm reads its
resource-policy annotation, ArgoCD its own sync option.
*/}}
{{- define "socle-lib.persistence" -}}
{{- include "socle-lib.uniqueNames" (dict "key" "persistence" "items" .Values.persistence) -}}
{{- range .Values.persistence }}
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  {{- include "socle-lib.metadata" (dict "root" $ "name" (include "socle-lib.objectName" (dict "root" $ "name" .name))) | nindent 2 }}
  {{- if ne .keep false }}
  annotations:
    helm.sh/resource-policy: keep
    argocd.argoproj.io/sync-options: Delete=false
  {{- end }}
spec:
  accessModes:
    {{- toYaml (.accessModes | default (list "ReadWriteOnce")) | nindent 4 }}
  {{- with .storageClassName }}
  storageClassName: {{ . }}
  {{- end }}
  resources:
    requests:
      storage: {{ .size }}
{{- end }}
{{- end -}}

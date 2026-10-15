{{/*
The pod spec both charts run: the release's ServiceAccount, the restricted
profile, the placement, the container, and an emptyDir on /tmp under the
read-only root filesystem. A Deployment wraps it in apps/v1, a CronJob in
batch/v1. pod is the calling chart's own pod fields (webapp's spread,
cronjob's restartPolicy), container its own container fields, both as YAML.
Takes (dict "root" . "pod" "<yaml>" "container" "<yaml>").
*/}}
{{- define "socle-lib.podSpec" -}}
{{- $v := .root.Values -}}
{{- $sc := $v.securityContext -}}
serviceAccountName: {{ include "socle-lib.fullname" .root }}
automountServiceAccountToken: {{ $v.serviceAccount.automountServiceAccountToken }}
{{- with $v.image.imagePullSecrets }}
imagePullSecrets:
  {{- toYaml . | nindent 2 }}
{{- end }}
securityContext:
  runAsNonRoot: true
  runAsUser: {{ $sc.runAsUser }}
  {{- with $sc.runAsGroup }}
  runAsGroup: {{ . }}
  {{- end }}
  {{- with $sc.fsGroup }}
  fsGroup: {{ . }}
  {{- end }}
  seccompProfile:
    type: RuntimeDefault
terminationGracePeriodSeconds: {{ $v.terminationGracePeriodSeconds }}
{{- with $v.nodeSelector }}
nodeSelector:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with $v.tolerations }}
tolerations:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with $v.affinity }}
affinity:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .pod }}
{{ . }}
{{- end }}
containers:
  {{- include "socle-lib.container" (dict "root" .root "extra" .container) | nindent 2 }}
volumes:
  - name: tmp
    emptyDir: {}
  {{- with $v.volumes }}
  {{- toYaml . | nindent 2 }}
  {{- end }}
{{- end -}}

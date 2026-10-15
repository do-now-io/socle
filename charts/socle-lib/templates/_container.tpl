{{/* The image, fully qualified: registry/repository:tag, or @digest. */}}
{{- define "socle-lib.image" -}}
{{- $i := .Values.image -}}
{{- if $i.tag -}}
{{- printf "%s/%s:%s" $i.registry $i.repository $i.tag -}}
{{- else -}}
{{- printf "%s/%s@%s" $i.registry $i.repository $i.digest -}}
{{- end -}}
{{- end -}}

{{/*
The application's container. The restricted profile is written here and
nowhere else: the values can only add NET_BIND_SERVICE back. commonEnv and
commonEnvFrom come first, so that the application's own win. extra is the
calling chart's own fields (webapp's port and probes), as YAML.
Takes (dict "root" . "extra" "<yaml>").
*/}}
{{- define "socle-lib.container" -}}
{{- $v := .root.Values -}}
- name: app
  image: {{ include "socle-lib.image" .root }}
  imagePullPolicy: {{ $v.image.pullPolicy }}
  {{- with $v.command }}
  command:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $v.args }}
  args:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with concat ($v.commonEnv | default list) ($v.env | default list) }}
  env:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with concat ($v.commonEnvFrom | default list) ($v.envFrom | default list) }}
  envFrom:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with .extra }}
  {{- . | nindent 2 }}
  {{- end }}
  {{- /* No limits unless set: an empty one would only be noise. */}}
  {{- $resources := deepCopy $v.resources }}
  {{- if empty $resources.limits }}
  {{- $_ := unset $resources "limits" }}
  {{- end }}
  resources:
    {{- toYaml $resources | nindent 4 }}
  securityContext:
    allowPrivilegeEscalation: false
    readOnlyRootFilesystem: true
    capabilities:
      drop: [ALL]
      {{- if $v.securityContext.netBindService }}
      add: [NET_BIND_SERVICE]
      {{- end }}
  volumeMounts:
    - name: tmp
      mountPath: /tmp
    {{- with $v.volumeMounts }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
{{- end -}}

{{/*
"true" when the pod reads a ConfigMap or a Secret: through envFrom, an env
variable's valueFrom, or a volume. Reloader is asked to roll the pods then.
*/}}
{{- define "socle-lib.readsConfig" -}}
{{- $v := .Values -}}
{{- $reads := false -}}
{{- if or $v.commonEnvFrom $v.envFrom -}}
{{- $reads = true -}}
{{- end -}}
{{- range concat ($v.commonEnv | default list) ($v.env | default list) -}}
{{- if and .valueFrom (or .valueFrom.configMapKeyRef .valueFrom.secretKeyRef) -}}
{{- $reads = true -}}
{{- end -}}
{{- end -}}
{{- range $v.volumes -}}
{{- if or .configMap .secret .projected -}}
{{- $reads = true -}}
{{- end -}}
{{- end -}}
{{- if $reads }}true{{ end -}}
{{- end -}}

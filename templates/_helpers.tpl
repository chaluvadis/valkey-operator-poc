{{- define "valkey-cluster.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "valkey-cluster.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name (include "valkey-cluster.name" .) | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{- define "valkey-cluster.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "valkey-cluster.labels" -}}
helm.sh/chart: {{ include "valkey-cluster.chart" . }}
{{ include "valkey-cluster.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | default .Values.image.tag | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{- define "valkey-cluster.selectorLabels" -}}
app.kubernetes.io/name: {{ include "valkey-cluster.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "valkey-cluster.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "valkey-cluster.fullname" .) .Values.serviceAccount.name }}
{{- else }}
default
{{- end }}
{{- end }}

{{- define "valkey-cluster.image" -}}
{{- printf "%s:%s" .Values.image.repository .Values.image.tag }}
{{- end }}
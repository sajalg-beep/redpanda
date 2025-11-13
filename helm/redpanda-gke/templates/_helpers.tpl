{{/*
Expand the name of the chart.
*/}}
{{- define "redpanda-gke.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "redpanda-gke.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "redpanda-gke.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "redpanda-gke.labels" -}}
helm.sh/chart: {{ include "redpanda-gke.chart" . }}
{{ include "redpanda-gke.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.additionalLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "redpanda-gke.selectorLabels" -}}
app.kubernetes.io/name: {{ include "redpanda-gke.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app: redpanda
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "redpanda-gke.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "redpanda-gke.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Create the namespace
*/}}
{{- define "redpanda-gke.namespace" -}}
{{- default .Release.Namespace .Values.namespace.name }}
{{- end }}

{{/*
Internal service name
*/}}
{{- define "redpanda-gke.serviceName" -}}
{{ include "redpanda-gke.fullname" . }}-internal
{{- end }}

{{/*
Full internal FQDN for brokers
*/}}
{{- define "redpanda-gke.internalFQDN" -}}
{{ include "redpanda-gke.serviceName" . }}.{{ include "redpanda-gke.namespace" . }}.svc.cluster.local
{{- end }}

{{/*
Pod anti-affinity
*/}}
{{- define "redpanda-gke.podAntiAffinity" -}}
{{- if eq .Values.highAvailability.podAntiAffinity.type "hard" }}
requiredDuringSchedulingIgnoredDuringExecution:
  - labelSelector:
      matchExpressions:
        - key: app
          operator: In
          values:
            - redpanda
    topologyKey: kubernetes.io/hostname
preferredDuringSchedulingIgnoredDuringExecution:
  - weight: 100
    podAffinityTerm:
      labelSelector:
        matchExpressions:
          - key: app
            operator: In
            values:
              - redpanda
      topologyKey: topology.kubernetes.io/zone
{{- else if eq .Values.highAvailability.podAntiAffinity.type "soft" }}
preferredDuringSchedulingIgnoredDuringExecution:
  - weight: 100
    podAffinityTerm:
      labelSelector:
        matchExpressions:
          - key: app
            operator: In
            values:
              - redpanda
      topologyKey: kubernetes.io/hostname
  - weight: 50
    podAffinityTerm:
      labelSelector:
        matchExpressions:
          - key: app
            operator: In
            values:
              - redpanda
      topologyKey: topology.kubernetes.io/zone
{{- end }}
{{- end }}

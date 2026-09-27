{{/* ---------------------------------------------------------------------
Names and labels
--------------------------------------------------------------------- */}}

{{- define "typo3.name" -}}
{{- default "typo3" .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "typo3.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else if contains "typo3" .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "typo3.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "typo3.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "typo3.labels" -}}
helm.sh/chart: {{ include "typo3.chart" . }}
app.kubernetes.io/name: {{ include "typo3.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: typo3
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{/* Release-wide selector (all components). */}}
{{- define "typo3.releaseSelector" -}}
app.kubernetes.io/name: {{ include "typo3.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/* Usage: include "typo3.selectorLabels" (dict "ctx" . "component" "app") */}}
{{- define "typo3.selectorLabels" -}}
{{ include "typo3.releaseSelector" .ctx }}
app.kubernetes.io/component: {{ .component }}
{{- end -}}

{{- define "typo3.componentLabels" -}}
{{ include "typo3.labels" .ctx }}
app.kubernetes.io/component: {{ .component }}
{{- end -}}

{{- define "typo3.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "typo3.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{- define "typo3.valkeyName" -}}
{{- printf "%s-valkey" (include "typo3.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* ---------------------------------------------------------------------
Validation. `required` only warns under `helm lint`, so the chart lints with
its defaults and still refuses to install without the mandatory values.
--------------------------------------------------------------------- */}}

{{- define "typo3.image" -}}
{{- $repo := required "image.repository is required (the FrankenPHP/PHP runtime image)" .Values.image.repository -}}
{{- if .Values.image.digest -}}
{{- printf "%s@%s" $repo .Values.image.digest -}}
{{- else -}}
{{- printf "%s:%s" $repo (required "image.tag or image.digest is required" .Values.image.tag) -}}
{{- end -}}
{{- end -}}

{{- define "typo3.artifact" -}}
{{- required "code.artifact is required (OCI reference of the signed code artefact)" .Values.code.artifact -}}
{{- end -}}

{{- define "typo3.secretName" -}}
{{- if .Values.secrets.existingSecret -}}
{{- .Values.secrets.existingSecret -}}
{{- else if .Values.secrets.externalSecret.enabled -}}
{{- printf "%s-secrets" (include "typo3.fullname" .) -}}
{{- else -}}
{{- required "set secrets.existingSecret or enable secrets.externalSecret" .Values.secrets.existingSecret -}}
{{- end -}}
{{- end -}}

{{- define "typo3.cosignConfigMap" -}}
{{- if .Values.code.verify.existingConfigMap -}}
{{- .Values.code.verify.existingConfigMap -}}
{{- else -}}
{{- printf "%s-cosign" (include "typo3.fullname" .) -}}
{{- end -}}
{{- end -}}

{{- define "typo3.healthHost" -}}
{{- default .Values.ingress.host .Values.app.health.host -}}
{{- end -}}

{{- define "typo3.validate" -}}
{{- if and .Values.code.verify.enabled (not .Values.code.verify.publicKey) (not .Values.code.verify.existingConfigMap) -}}
{{- required "code.verify.publicKey or code.verify.existingConfigMap is required while code.verify.enabled=true" "" -}}
{{- end -}}
{{- if and .Values.valkey.enabled .Values.valkey.tls.enabled (not .Values.internalTls.enabled) -}}
{{- fail "valkey.tls.enabled requires internalTls.enabled" -}}
{{- end -}}
{{- if and .Values.database.tls.enabled .Values.database.tls.clientCertificate (not .Values.internalTls.enabled) -}}
{{- fail "database.tls.clientCertificate requires internalTls.enabled" -}}
{{- end -}}
{{- if and .Values.database.tls.enabled (not .Values.database.tls.caSecret.name) (not .Values.internalTls.enabled) -}}
{{- fail "database.tls needs either database.tls.caSecret.name or internalTls.enabled" -}}
{{- end -}}
{{- if and .Values.backup.enabled (not (has .Values.backup.target (list "pvc" "s3"))) -}}
{{- fail "backup.target must be \"pvc\" or \"s3\"" -}}
{{- end -}}
{{- end -}}

{{/* ---------------------------------------------------------------------
Security contexts
--------------------------------------------------------------------- */}}

{{- define "typo3.podSecurityContext" -}}
runAsNonRoot: true
seccompProfile:
  type: RuntimeDefault
fsGroupChangePolicy: OnRootMismatch
{{- with . }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{/* Every container, init containers included: read-only root, no
privilege escalation, no capabilities, RuntimeDefault seccomp. */}}
{{- define "typo3.containerSecurityContext" -}}
runAsNonRoot: true
allowPrivilegeEscalation: false
readOnlyRootFilesystem: true
privileged: false
capabilities:
  drop: ["ALL"]
seccompProfile:
  type: RuntimeDefault
{{- end -}}

{{/* ---------------------------------------------------------------------
Issuer and TLS
--------------------------------------------------------------------- */}}

{{- define "typo3.issuerRef" -}}
{{- if .Values.internalTls.issuer.create -}}
name: {{ include "typo3.fullname" . }}-ca
kind: Issuer
group: cert-manager.io
{{- else -}}
name: {{ required "internalTls.issuer.existing.name is required when internalTls.issuer.create=false" .Values.internalTls.issuer.existing.name }}
kind: {{ .Values.internalTls.issuer.existing.kind }}
group: {{ .Values.internalTls.issuer.existing.group }}
{{- end -}}
{{- end -}}

{{- define "typo3.dbCaPath" -}}
{{- if .Values.database.tls.caSecret.name -}}/run/tls-db/ca.crt{{- else -}}/run/tls/ca.crt{{- end -}}
{{- end -}}

{{/* ---------------------------------------------------------------------
Shared pod parts for the app Deployment and the scheduler CronJob
--------------------------------------------------------------------- */}}

{{/* Init containers that verify and fetch the code artefact. */}}
{{- define "typo3.codeInitContainers" -}}
{{- $artifact := include "typo3.artifact" . -}}
{{- if .Values.code.verify.enabled }}
- name: cosign-verify
  image: {{ .Values.code.verify.image | quote }}
  securityContext:
    {{- include "typo3.containerSecurityContext" . | nindent 4 }}
    runAsUser: 65532
    runAsGroup: 65532
  env:
    - { name: DOCKER_CONFIG, value: /run/docker }
    - { name: HOME, value: /tmp }
  args:
    - verify
    - --key=/run/cosign/cosign.pub
    {{- if .Values.code.verify.ignoreTlog }}
    - --insecure-ignore-tlog=true
    {{- end }}
    - --output=text
    - {{ $artifact | quote }}
  volumeMounts:
    - { name: cosign-key, mountPath: /run/cosign, readOnly: true }
    - { name: tmp, mountPath: /tmp }
    {{- if .Values.code.pullSecret }}
    - { name: registry-auth, mountPath: /run/docker, readOnly: true }
    {{- end }}
  resources:
    {{- toYaml .Values.code.verify.resources | nindent 4 }}
{{- if .Values.code.verify.attestation.enabled }}
- name: cosign-verify-attestation
  image: {{ .Values.code.verify.image | quote }}
  securityContext:
    {{- include "typo3.containerSecurityContext" . | nindent 4 }}
    runAsUser: 65532
    runAsGroup: 65532
  env:
    - { name: DOCKER_CONFIG, value: /run/docker }
    - { name: HOME, value: /tmp }
  args:
    - verify-attestation
    - --key=/run/cosign/cosign.pub
    - --type={{ .Values.code.verify.attestation.type }}
    {{- if .Values.code.verify.ignoreTlog }}
    - --insecure-ignore-tlog=true
    {{- end }}
    - --output=text
    - {{ $artifact | quote }}
  volumeMounts:
    - { name: cosign-key, mountPath: /run/cosign, readOnly: true }
    - { name: tmp, mountPath: /tmp }
    {{- if .Values.code.pullSecret }}
    - { name: registry-auth, mountPath: /run/docker, readOnly: true }
    {{- end }}
  resources:
    {{- toYaml .Values.code.verify.resources | nindent 4 }}
{{- end }}
{{- end }}
- name: fetch-code
  image: {{ .Values.code.oras.image | quote }}
  securityContext:
    {{- include "typo3.containerSecurityContext" . | nindent 4 }}
    runAsUser: {{ .Values.app.podSecurityContext.runAsUser | default 1000 }}
    runAsGroup: {{ .Values.app.podSecurityContext.runAsGroup | default 1000 }}
  env:
    - { name: DOCKER_CONFIG, value: /run/docker }
    - { name: HOME, value: /tmp }
    - { name: ARTIFACT, value: {{ $artifact | quote }} }
    - { name: ARTIFACT_FILE, value: {{ .Values.code.file | quote }} }
  command: ["/bin/sh", "-c"]
  args:
    - |
      set -eu
      mkdir -p /tmp/pull
      ok=""
      for attempt in $(seq 1 {{ .Values.code.oras.retries | int }}); do
        if oras pull "$ARTIFACT" -o /tmp/pull; then ok=1; break; fi
        echo "fetch-code: pull attempt ${attempt} failed, retrying in $((attempt * 10))s" >&2
        sleep $((attempt * 10))
      done
      [ -n "$ok" ] || { echo "fetch-code: giving up after {{ .Values.code.oras.retries | int }} attempts" >&2; exit 1; }
      [ -f "/tmp/pull/$ARTIFACT_FILE" ] || { echo "fetch-code: $ARTIFACT_FILE not found in the artefact" >&2; exit 1; }
      tar -xf "/tmp/pull/$ARTIFACT_FILE" -C /app
      rm -rf /tmp/pull
      # Writable directories that are not part of the artefact. They also act
      # as mount points for the writable sub-mounts of a read-only /app.
      mkdir -p /app/var/cache /app/var/lock /app/var/log /app/var/session \
               /app/public/typo3temp/assets /app/public/typo3temp/var \
               /app/public/_assets
      echo "fetch-code: $ARTIFACT unpacked"
  volumeMounts:
    - { name: code, mountPath: /app }
    - { name: tmp, mountPath: /tmp }
    {{- if .Values.code.pullSecret }}
    - { name: registry-auth, mountPath: /run/docker, readOnly: true }
    {{- end }}
  resources:
    {{- toYaml .Values.code.oras.resources | nindent 4 }}
{{- end -}}

{{/* Environment of every container that runs TYPO3. The application reads
secrets from files (the *_FILE variables), never from the environment. */}}
{{- define "typo3.appEnv" -}}
- { name: TYPO3_CONTEXT, value: {{ .Values.app.typo3Context | quote }} }
- { name: HOME, value: /tmp }
- { name: SERVER_NAME, value: ":{{ .Values.app.port }}" }
- { name: XDG_CONFIG_HOME, value: /tmp/xdg-config }
- { name: XDG_DATA_HOME, value: /tmp/xdg-data }
{{- if .Values.database.host }}
- { name: TYPO3_DB_HOST, value: {{ .Values.database.host | quote }} }
{{- else }}
- { name: TYPO3_DB_HOST_FILE, value: /run/secrets/typo3/db-host }
{{- end }}
- { name: TYPO3_DB_PORT, value: {{ .Values.database.port | quote }} }
- { name: TYPO3_DB_NAME, value: {{ .Values.database.name | quote }} }
- { name: TYPO3_DB_USER_FILE, value: /run/secrets/typo3/db-user }
- { name: TYPO3_DB_PASSWORD_FILE, value: /run/secrets/typo3/db-password }
{{- if .Values.database.tls.enabled }}
- { name: TYPO3_DB_SSL_CA, value: {{ include "typo3.dbCaPath" . | quote }} }
- { name: TYPO3_DB_SSL_VERIFY_SERVER_CERT, value: {{ .Values.database.tls.verifyServerCertificate | quote }} }
{{- if .Values.database.tls.clientCertificate }}
- { name: TYPO3_DB_SSL_CERT, value: /run/tls/tls.crt }
- { name: TYPO3_DB_SSL_KEY, value: /run/tls/tls.key }
{{- end }}
{{- end }}
- { name: TYPO3_ENCRYPTION_KEY_FILE, value: /run/secrets/typo3/encryption-key }
{{- if .Values.valkey.enabled }}
- { name: VALKEY_HOST, value: {{ include "typo3.valkeyName" . | quote }} }
- { name: VALKEY_PORT, value: {{ .Values.valkey.port | quote }} }
- { name: VALKEY_PASSWORD_FILE, value: /run/secrets/typo3/valkey-password }
- { name: VALKEY_TLS, value: {{ .Values.valkey.tls.enabled | quote }} }
{{- if .Values.valkey.tls.enabled }}
- { name: VALKEY_TLS_CA, value: /run/tls/ca.crt }
- { name: VALKEY_TLS_CERT, value: /run/tls/tls.crt }
- { name: VALKEY_TLS_KEY, value: /run/tls/tls.key }
{{- end }}
{{- end }}
{{- range $k, $v := .Values.app.env }}
- { name: {{ $k | quote }}, value: {{ $v | quote }} }
{{- end }}
{{- with .Values.app.extraEnv }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{/* Secret and TLS mounts of every container that runs TYPO3. */}}
{{- define "typo3.appSecretMounts" -}}
- { name: secrets, mountPath: /run/secrets/typo3, readOnly: true }
{{- if .Values.internalTls.enabled }}
- { name: tls, mountPath: /run/tls, readOnly: true }
{{- end }}
{{- if and .Values.database.tls.enabled .Values.database.tls.caSecret.name }}
- { name: tls-db, mountPath: /run/tls-db, readOnly: true }
{{- end }}
{{- end -}}

{{/* Mounts of the running TYPO3 container (app and scheduler). */}}
{{- define "typo3.appRuntimeMounts" -}}
- { name: code, mountPath: /app{{ if .Values.app.readOnlyAppCode }}, readOnly: true{{ end }} }
{{- if .Values.app.readOnlyAppCode }}
- { name: code, mountPath: /app/var, subPath: var }
- { name: code, mountPath: /app/public/typo3temp, subPath: public/typo3temp }
- { name: code, mountPath: /app/public/_assets, subPath: public/_assets }
{{- end }}
- { name: tmp, mountPath: /tmp }
{{ include "typo3.appSecretMounts" . }}
{{- end -}}

{{/* Volumes shared by the app Deployment and the scheduler CronJob. */}}
{{- define "typo3.appVolumes" -}}
- name: code
  emptyDir:
    sizeLimit: {{ .Values.code.sizeLimit }}
- name: tmp
  emptyDir:
    sizeLimit: 512Mi
{{- if .Values.code.verify.enabled }}
- name: cosign-key
  configMap:
    name: {{ include "typo3.cosignConfigMap" . }}
    items:
      - { key: cosign.pub, path: cosign.pub }
{{- end }}
{{- if and .Values.app.setup.enabled .Values.app.setup.lock.enabled }}
- name: setup-lock
  configMap:
    name: {{ include "typo3.fullname" . }}-setup-lock
{{- end }}
{{- if .Values.code.pullSecret }}
- name: registry-auth
  secret:
    secretName: {{ .Values.code.pullSecret }}
    items:
      - { key: .dockerconfigjson, path: config.json }
{{- end }}
- name: secrets
  secret:
    secretName: {{ include "typo3.secretName" . }}
    defaultMode: 0440
    items:
      {{- if not .Values.database.host }}
      - { key: {{ .Values.secrets.keys.dbHost }}, path: db-host }
      {{- end }}
      - { key: {{ .Values.secrets.keys.dbUser }}, path: db-user }
      - { key: {{ .Values.secrets.keys.dbPassword }}, path: db-password }
      - { key: {{ .Values.secrets.keys.encryptionKey }}, path: encryption-key }
      {{- if .Values.valkey.enabled }}
      - { key: {{ .Values.secrets.keys.valkeyPassword }}, path: valkey-password }
      {{- end }}
{{- if .Values.internalTls.enabled }}
- name: tls
  secret:
    secretName: {{ include "typo3.fullname" . }}-app-tls
    defaultMode: 0440
{{- end }}
{{- if and .Values.database.tls.enabled .Values.database.tls.caSecret.name }}
- name: tls-db
  secret:
    secretName: {{ .Values.database.tls.caSecret.name }}
    defaultMode: 0444
    items:
      - { key: {{ .Values.database.tls.caSecret.key }}, path: ca.crt }
{{- end }}
{{- end -}}

{{/* "Anywhere" peer list, used when a flow has no narrower peers configured. */}}
{{- define "typo3.anyPeers" -}}
- ipBlock: { cidr: 0.0.0.0/0 }
- ipBlock: { cidr: "::/0" }
{{- end -}}

{{/* Egress rules shared by the app and scheduler NetworkPolicies. */}}
{{- define "typo3.appEgress" -}}
{{- $np := .Values.networkPolicy -}}
{{- if .Values.valkey.enabled }}
- to:
    - podSelector:
        matchLabels:
          {{- include "typo3.selectorLabels" (dict "ctx" . "component" "valkey") | nindent 10 }}
  ports:
    - { protocol: TCP, port: {{ .Values.valkey.port }} }
{{- end }}
- to:
    {{- if $np.database.to }}
    {{- toYaml $np.database.to | nindent 4 }}
    {{- else }}
    {{- include "typo3.anyPeers" . | nindent 4 }}
    {{- end }}
  ports:
    - { protocol: TCP, port: {{ .Values.database.port }} }
- to:
    {{- if $np.registry.to }}
    {{- toYaml $np.registry.to | nindent 4 }}
    {{- else }}
    {{- include "typo3.anyPeers" . | nindent 4 }}
    {{- end }}
  ports:
    - { protocol: TCP, port: {{ $np.registry.port }} }
{{- with $np.extraAppEgress }}
{{ toYaml . }}
{{- end }}
{{- end -}}

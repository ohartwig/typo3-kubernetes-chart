# Changelog

All notable changes to this chart are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the chart
follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.0] - 2026-09-27

### Added

- TYPO3 Deployment on FrankenPHP (HTTP 8080), Service and Ingress.
- Code delivery as an OCI artefact: `cosign verify` (optionally
  `verify-attestation`) and `oras pull` initContainers, read-only code mount.
- Setup initContainer (`extension:setup`, `cache:warmup`).
- TYPO3 scheduler as a CronJob with `concurrencyPolicy: Forbid`.
- Valkey StatefulSet for cache and sessions, TLS 1.3 with client
  certificates, password auth, certificate reload sidecar.
- Namespaced CA and leaf certificates via cert-manager.
- ExternalSecret for database credentials, encryption key and Valkey password.
- NetworkPolicies: namespace default deny, per-component allows.
- HorizontalPodAutoscaler, PodDisruptionBudget, topology spread constraints.
- Optional database backup CronJob to a PVC or S3-compatible storage.
- `helm test` health check, values schema, three CI value profiles.

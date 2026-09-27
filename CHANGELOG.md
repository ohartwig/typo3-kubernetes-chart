# Changelog

All notable changes to this chart are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the chart
follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.2.0] - 2026-09-27

### Added

- `secrets.extra`: additional secrets for TYPO3, mounted as files under
  `/run/secrets/typo3/extra/` with a `<NAME>_FILE` variable in every TYPO3
  container, so resolvers that read `<NAME>_FILE` (for example `%secret()%`
  placeholders) work without further wiring. Fetched through the
  ExternalSecret like the built-in keys.
- Dependency updates by pinup (`.pinup.yaml`, `.github/workflows/pinup.yml`)
  for the pinned actions, tools and default images.

### Changed

- GitHub is the only home of the chart; the GitLab pipeline is gone.
- gitleaks runs from its container image, pinned like every other tool.

## [0.1.1] - 2026-09-27

### Fixed

- The verify initContainer now runs cosign 3.0.6 instead of 2.6.1. cosign 3
  signs in the Sigstore bundle format by default, which cosign 2 cannot find;
  an artefact signed with a current cosign therefore kept every pod from
  starting. cosign 3 verifies both formats.

## [0.1.0] - 2026-09-27

First public release.

### Added

- TYPO3 Deployment on FrankenPHP (HTTP 8080), Service and Ingress.
- Code delivery as an OCI artefact: `cosign verify` (optionally
  `verify-attestation`) and `oras pull` initContainers, read-only code mount.
- Setup initContainer (`extension:setup`, `cache:warmup`), serialised across
  pods with a database advisory lock (`app.setup.lock`).
- TYPO3 scheduler as a CronJob with `concurrencyPolicy: Forbid`.
- Valkey StatefulSet for cache and sessions, TLS 1.3 with client
  certificates, password auth, certificate reload sidecar.
- Namespaced CA and leaf certificates via cert-manager.
- ExternalSecret for database credentials, encryption key and Valkey password.
- NetworkPolicies: namespace default deny, per-component allows.
- HorizontalPodAutoscaler, PodDisruptionBudget, topology spread constraints.
- Optional database backup CronJob to a PVC or S3-compatible storage.
- `helm test` health check, values schema, three CI value profiles.
- GitHub Actions: CI (lint, render, kubeconform, gitleaks, REUSE) and a
  release workflow that pushes the chart to an OCI registry and signs it
  keylessly with cosign.
- Threat model (`docs/threat-model.md`), code of conduct, issue and pull
  request templates.

[Unreleased]: https://github.com/ohartwig/typo3-kubernetes-chart/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/ohartwig/typo3-kubernetes-chart/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/ohartwig/typo3-kubernetes-chart/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/ohartwig/typo3-kubernetes-chart/releases/tag/v0.1.0

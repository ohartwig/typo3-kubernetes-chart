# Security policy

## Reporting a vulnerability

Please report security issues privately by e-mail to
**security@ole-hartwig.eu** — not through public issues or merge requests.

Include what you found, how to reproduce it (values and rendered manifests
help) and the chart version. You will get an acknowledgement within five
working days and a first assessment within ten.

## Scope

In scope: the templates of this chart and their defaults — for example a
container that ends up with more privileges than documented, a NetworkPolicy
that allows more than it says, or a secret that is rendered into a manifest.

Out of scope: vulnerabilities in TYPO3, FrankenPHP, Valkey, cert-manager,
External Secrets Operator, cosign or oras themselves. Please report those to
the respective projects.

## Supported versions

Only the latest released minor version receives fixes.

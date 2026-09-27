# Contributing

Thank you for considering a contribution. Development happens on GitHub:
issues and pull requests at
<https://github.com/ohartwig/typo3-kubernetes-chart>. This chart is a reference
implementation for a blog series, so the bar is readability first: a change
that adds a feature should also explain, in a comment or in the README, why
the feature is there.

## Before you open a pull request

- `helm lint --strict .` passes.
- `helm template` passes for all three profiles in `ci/`, and the output
  validates with `kubeconform -strict`.
- New optional features are behind a switch in `values.yaml`, default to the
  safe choice, and are documented there with a comment.
- New values that users are expected to set are added to `values.schema.json`.
- Every container keeps the hardened security context (non-root, read-only
  root filesystem, no capabilities, `RuntimeDefault` seccomp).
- The chart stays generic: no real host names, registries, account IDs, IP
  ranges or organisation names in templates, values, examples or tests. Use
  `example.org`/`example.com` and the documentation IP ranges (RFC 5737).
- Documentation is written in British English.

## Developer Certificate of Origin

Every commit must be signed off, certifying the
[Developer Certificate of Origin](https://developercertificate.org/):

```
git commit -s
```

## Signed commits

Commits must also carry a verifiable signature (SSH or GPG):

```
git config commit.gpgsign true
```

## Licence

By contributing you agree that your contribution is licensed under the
Apache License 2.0, like the rest of the repository.

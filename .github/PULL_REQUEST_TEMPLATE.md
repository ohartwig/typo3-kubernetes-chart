## What and why

<!-- What does this change, and why is it needed? -->

## Checklist

- [ ] Every commit is signed off (`git commit -s`, Developer Certificate of Origin) and signed.
- [ ] `helm lint --strict .` passes, also with each profile in `ci/`.
- [ ] `helm template` output of all profiles validates with `kubeconform -strict`.
- [ ] New options default to the safe choice and are documented in `values.yaml`.
- [ ] Values users are expected to set are in `values.schema.json`.
- [ ] Containers keep the hardened security context.
- [ ] No real host names, registries, account IDs or organisation names.
- [ ] `CHANGELOG.md` has an entry under `[Unreleased]`.

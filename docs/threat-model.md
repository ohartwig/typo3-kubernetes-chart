# Threat model

A STRIDE view of what this chart deploys: which assets it protects, where the
trust boundaries run, what the chart does about each threat, and what it
leaves to the platform around it. It describes the chart's defaults; every
switch that weakens one of them is called out in `values.yaml`.

## Assets

| Asset | Why it matters |
|---|---|
| Code artefact | Everything the pods execute. Whoever controls it controls the site. |
| Secrets | Database credentials, TYPO3 `encryptionKey`, Valkey password, TLS keys. |
| Database | Content, backend users, sessions of record. |
| Valkey | Caches and sessions; a poisoned cache serves attacker content to every visitor. |
| Internal CA | Issues the certificates that every mTLS connection trusts. |

## Trust boundaries

```
 registry ──(1)──► TYPO3 pod ──(2)──► database
                      │  ▲
                      │  └──(3)── Ingress controller ◄── internet
                      └──(2)──► Valkey
 Kubernetes API ──(4)── (no token mounted in any pod)
```

1. **Registry → pod**: code and images cross into the cluster.
2. **Pod → database / Valkey**: credentials and data leave the pod.
3. **Ingress → pod**: untrusted requests reach PHP.
4. **Pod → Kubernetes API**: a compromised pod trying to move sideways.

## Threats and mitigations

| STRIDE | Threat | Boundary | Mitigation in the chart |
|---|---|---|---|
| Spoofing | Forged or swapped code artefact | 1 | `cosign verify` against a pinned public key before `oras pull`; reference by digest so verify and pull see the same bytes; optional attestation check. |
| Spoofing | A pod impersonating TYPO3 towards Valkey or the database | 2 | mTLS with client certificates from a per-release CA; Valkey requires them and TLS 1.3. |
| Tampering | Modified code or configuration at runtime | — | Read-only root filesystem and read-only code mount; only `var/`, `typo3temp/` and `_assets/` stay writable. |
| Tampering | Two pods migrating the schema at once | 2 | Setup runs under a database advisory lock, one pod at a time. |
| Repudiation | Unattributable changes to content | — | Out of scope for the chart; use TYPO3 workspaces and central logging. |
| Information disclosure | Secrets in manifests, environment or Git | — | ExternalSecret renders a reference only; secrets reach the pods as files with mode `0440`, never as environment values. Exception: the S3 key pair of the optional backup. |
| Information disclosure | Traffic sniffed inside the cluster | 2 | TLS to the database and Valkey, server certificates verified. |
| Denial of service | One tenant exhausting the node | — | Resource requests and limits on every container; PodDisruptionBudget and topology spread for availability. |
| Elevation of privilege | Container escape or privilege gain | — | Restricted Pod Security Standard: non-root, no privilege escalation, all capabilities dropped, `RuntimeDefault` seccomp. |
| Elevation of privilege | Lateral movement from a compromised pod | 2, 4 | Namespace-wide default-deny NetworkPolicies with one allow per flow; no service account token mounted. |

## Residual risks and out of scope

- **Signing key compromise.** Whoever holds the private key can sign any
  artefact. Keep it in a KMS or use keyless signing; rotate it with the public
  key in `code.verify.publicKey`.
- **Registry compromise.** Mitigated by signature verification, not prevented.
  A registry outage stops new pods from starting.
- **Vulnerable dependencies.** The CVE gate belongs in CI, before signing. The
  cluster checks that the artefact was signed, not that it is free of flaws.
- **Web application attacks.** SQL injection, XSS or brute force against the
  backend are handled by TYPO3 itself and by a WAF or rate limiting in the
  Ingress layer, which this chart does not provide.
- **Database hardening.** The database runs outside the chart; its users,
  grants, encryption at rest and backups beyond the optional dump job are the
  operator's responsibility.
- **Broad egress defaults.** The allows for database, registry and backup
  target default to any address on the port. Narrow them to your peers.
- **Cluster compromise.** An attacker with cluster-admin rights can read every
  secret and bypass every control above. The chart assumes a hardened cluster.

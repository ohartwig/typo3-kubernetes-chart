# typo3-kubernetes-chart

A reference Helm chart for running [TYPO3](https://typo3.org) on Kubernetes with
the hardening you would expect under BSI IT-Grundschutz: signed code verified
before it runs, read-only containers without capabilities, mutual TLS between
application, cache and database, default-deny network policies and secrets that
never pass through a values file.

It accompanies part 14 of the blog series *"TYPO3 on Kubernetes under
IT-Grundschutz"*
([English](https://ole-hartwig.eu/en/blog/typo3-kubernetes-it-grundschutz-part-14-reference-chart),
[German](https://ole-hartwig.eu/blog/typo3-kubernetes-grundschutz-teil-14-referenz-chart)).
The articles explain the reasoning behind each building block; this chart puts
the blocks together so you can install, read and adapt them.

It is a **reference**, not a product: small enough to read in an afternoon,
opinionated where security is concerned, and deliberately silent on everything
that differs from one platform to the next.

## What it deploys

| Component | Kind | Purpose |
|---|---|---|
| TYPO3 | Deployment, Service, Ingress | FrankenPHP serving TYPO3 on HTTP 8080 behind your Ingress controller |
| Code delivery | initContainers | `cosign verify` of the code artefact, then `oras pull` into an `emptyDir` |
| Setup | initContainer | `extension:setup` and `cache:warmup` before the first request, one pod at a time |
| Scheduler | CronJob | `scheduler:run`, `concurrencyPolicy: Forbid` |
| Valkey | StatefulSet, Service | Cache and session store, TLS with client certificates, password auth |
| Internal PKI | cert-manager Issuers, Certificates | A CA per release namespace, short-lived leaf certificates |
| Secrets | ExternalSecret | Database credentials, TYPO3 `encryptionKey`, Valkey password |
| Network | NetworkPolicies | Default deny, one explicit allow per flow and component |
| Availability | HPA, PodDisruptionBudget, topology spread | Optional autoscaling, safe drains, spread over zones and nodes |
| Backup | CronJob (+ PVC) | Optional `mariadb-dump` to a PVC or S3-compatible storage |
| Test | Pod (`helm test`) | One HTTP request against the health path |

```
                Ingress controller
                       │ HTTP :8080
        ┌──────────────▼──────────────┐        ┌───────────────────┐
        │ TYPO3 pod                   │  mTLS  │ Valkey            │
        │  init: cosign verify        ├───────►│ cache + sessions  │
        │  init: oras pull            │        └───────────────────┘
        │  init: typo3 setup          │  mTLS  ┌───────────────────┐
        │  FrankenPHP (read-only)     ├───────►│ MariaDB/MySQL     │
        └─────────────────────────────┘        │ (external)        │
                                               └───────────────────┘
```

## Prerequisites

- Kubernetes 1.30 or later, with a CNI that enforces NetworkPolicies.
- [cert-manager](https://cert-manager.io) (1.13+) for the internal CA and certificates.
- [External Secrets Operator](https://external-secrets.io) (0.17+, `external-secrets.io/v1`)
  and a `SecretStore` or `ClusterSecretStore` — or a Secret you create yourself.
- An Ingress controller.
- An external MariaDB or MySQL database, reachable over TLS.
- An OCI registry that holds
  - the **runtime image** (PHP + FrankenPHP, no application code), and
  - the **code artefact**: your Composer-built TYPO3 project as a tarball,
    pushed with `oras` and signed with `cosign`.
- The **cosign public key** the artefact was signed with.
- S3-compatible object storage for `fileadmin` (see [Files and uploads](#files-and-uploads)).

## Quick start

1. Create a namespace per tenant and enforce the restricted Pod Security Standard:

   ```bash
   kubectl create namespace tenant-a
   kubectl label namespace tenant-a \
     pod-security.kubernetes.io/enforce=restricted \
     pod-security.kubernetes.io/warn=restricted
   ```

2. Build, push and sign the code artefact in CI:

   ```bash
   composer install --no-dev --optimize-autoloader
   tar -czf app.tar.gz --exclude=.git .
   oras push registry.example.org/tenant-a/typo3-code:1.0.0 \
     app.tar.gz:application/vnd.oci.image.layer.v1.tar+gzip
   cosign sign --key cosign.key registry.example.org/tenant-a/typo3-code@sha256:<digest>
   ```

   The CVE gate belongs here as well, before signing: scan the image and the
   Composer lock file, and only sign what passed. The chart can additionally
   check an attestation (`code.verify.attestation`), but the decision itself is
   made in CI.

3. Store the credentials in your secret backend under one key with these
   properties: `db-host`, `db-user`, `db-password`, `encryption-key`,
   `valkey-password`.

4. Install:

   ```bash
   helm install tenant-a . --namespace tenant-a \
     --set image.repository=registry.example.org/tenant-a/typo3-runtime \
     --set image.tag=8.4-frankenphp \
     --set code.artifact=registry.example.org/tenant-a/typo3-code@sha256:<digest> \
     --set-file code.verify.publicKey=cosign.pub \
     --set ingress.host=typo3.example.org \
     --set secrets.externalSecret.secretStoreRef.name=tenant-a-store \
     --set secrets.externalSecret.remoteKey=tenant-a/typo3
   helm test tenant-a --namespace tenant-a
   ```

The commands above install from a checkout of this repository. Released
versions are also published as a signed OCI artefact.

### Installation from the OCI registry

```bash
helm install tenant-a oci://ghcr.io/ohartwig/charts/typo3-kubernetes-chart \
  --version 0.2.0 --namespace tenant-a \
  -f my-values.yaml
```

### Verifying the chart signature

Every release is signed keylessly by the release workflow of this repository.
Verify it before you install; no key is needed, the signature is bound to the
workflow and the tag. Use cosign 3 or later: the signature is stored in the
Sigstore bundle format, which cosign 2 does not find.

```bash
cosign verify ghcr.io/ohartwig/charts/typo3-kubernetes-chart:0.2.0 \
  --certificate-identity-regexp '^https://github\.com/ohartwig/typo3-kubernetes-chart/\.github/workflows/release\.yml@refs/tags/v' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

`ci/values-minimal.yaml`, `ci/values-full.yaml` and `ci/values-ha.yaml` show
the smallest release, every optional feature, and a high-availability setup.

## Runtime image contract

The chart does not ship a TYPO3 image. Yours has to:

- serve plain HTTP on `app.port` (8080). The chart sets `SERVER_NAME=:8080`,
  which the FrankenPHP images honour;
- run as a non-root user (`app.podSecurityContext`, default UID/GID 1000) and
  cope with a read-only root filesystem: writable are `/tmp`, `/app/var`,
  `/app/public/typo3temp` and `/app/public/_assets`. Caddy's config and data
  directories are pointed at `/tmp` via `XDG_CONFIG_HOME`/`XDG_DATA_HOME`;
- contain `/bin/sh`, for the setup initContainer;
- read its configuration from the environment variables below. Secrets are
  passed as **files**, never as environment values; the `*_FILE` variables
  name the path.

| Variable | Content |
|---|---|
| `TYPO3_CONTEXT` | `app.typo3Context` |
| `TYPO3_DB_HOST` / `TYPO3_DB_HOST_FILE` | Database host (literal, or from the secret) |
| `TYPO3_DB_PORT`, `TYPO3_DB_NAME` | Port and schema name |
| `TYPO3_DB_USER_FILE`, `TYPO3_DB_PASSWORD_FILE` | Credentials |
| `TYPO3_DB_SSL_CA`, `TYPO3_DB_SSL_CERT`, `TYPO3_DB_SSL_KEY` | TLS material for the database connection |
| `TYPO3_DB_SSL_VERIFY_SERVER_CERT` | `true` / `false` |
| `TYPO3_ENCRYPTION_KEY_FILE` | `$GLOBALS['TYPO3_CONF_VARS']['SYS']['encryptionKey']` |
| `VALKEY_HOST`, `VALKEY_PORT`, `VALKEY_PASSWORD_FILE` | Valkey connection |
| `VALKEY_TLS`, `VALKEY_TLS_CA`, `VALKEY_TLS_CERT`, `VALKEY_TLS_KEY` | Valkey TLS |

A minimal `config/system/additional.php` that maps them:

```php
<?php

$read = static fn (string $var): ?string =>
    ($path = getenv($var)) !== false && is_readable($path) ? trim((string) file_get_contents($path)) : null;

$db = &$GLOBALS['TYPO3_CONF_VARS']['DB']['Connections']['Default'];
$db['driver']   = 'mysqli';
$db['host']     = getenv('TYPO3_DB_HOST') ?: $read('TYPO3_DB_HOST_FILE');
$db['port']     = (int) getenv('TYPO3_DB_PORT');
$db['dbname']   = getenv('TYPO3_DB_NAME');
$db['user']     = $read('TYPO3_DB_USER_FILE');
$db['password'] = $read('TYPO3_DB_PASSWORD_FILE');
if (getenv('TYPO3_DB_SSL_CA')) {
    $db['ssl_ca']   = getenv('TYPO3_DB_SSL_CA');
    $db['ssl_cert'] = getenv('TYPO3_DB_SSL_CERT') ?: null;
    $db['ssl_key']  = getenv('TYPO3_DB_SSL_KEY') ?: null;
    $db['driverOptions']['flags'] = MYSQLI_CLIENT_SSL
        | (getenv('TYPO3_DB_SSL_VERIFY_SERVER_CERT') === 'true' ? 0 : MYSQLI_CLIENT_SSL_DONT_VERIFY_SERVER_CERT);
}

$GLOBALS['TYPO3_CONF_VARS']['SYS']['encryptionKey'] = $read('TYPO3_ENCRYPTION_KEY_FILE');
```

Wiring Valkey into the caching framework and the session backend depends on
the cache backend you use; the variables above carry everything it needs.

### Additional secrets and `%secret()%` placeholders

Every secret reaches the pod as a file, and a `<NAME>_FILE` variable names
the path. A resolver that reads `<NAME>_FILE` — for example a `%secret(NAME)%`
placeholder in site configuration or other YAML — therefore works without
further wiring:

- the built-in values resolve as `%secret(TYPO3_DB_PASSWORD)%`,
  `%secret(TYPO3_ENCRYPTION_KEY)%`, `%secret(VALKEY_PASSWORD)%` and so on,
  through the `*_FILE` variables in the table above;
- anything else TYPO3 needs — an SMTP password, an API token — goes into
  `secrets.extra`. Each entry becomes a key in the Secret (and a property of
  the remote secret, when the ExternalSecret is used), is mounted at
  `/run/secrets/typo3/extra/<key>`, and sets `<name>_FILE` in every TYPO3
  container:

  ```yaml
  secrets:
    extra:
      - name: SMTP_PASSWORD      # -> SMTP_PASSWORD_FILE, %secret(SMTP_PASSWORD)%
        key: smtp-password       # key in the Secret, file name in the pod
        property: smtp-password  # remote property; defaults to key
  ```

The chart mounts its secrets under `/run/secrets/typo3/`, not directly under
`/run/secrets/`. A resolver that only looks for `/run/secrets/<name>` does
not find them; use the `<NAME>_FILE` variables.

## Important values

The full list with comments is in [`values.yaml`](values.yaml); the schema in
[`values.schema.json`](values.schema.json) rejects the obvious mistakes.

| Key | Default | Description |
|---|---|---|
| `image.repository` / `image.tag` / `image.digest` | — | Runtime image. Required. |
| `code.artifact` | — | Code artefact reference. Required. Prefer `…@sha256:…`. |
| `code.file` | `app.tar.gz` | Tarball inside the artefact. |
| `code.pullSecret` | `""` | dockerconfigjson Secret for oras and cosign. |
| `code.verify.enabled` | `true` | Fail-closed signature check before the pull. |
| `code.verify.publicKey` / `existingConfigMap` | — | cosign public key. Required while verification is on. |
| `code.verify.attestation.enabled` | `false` | Also verify an attestation (e.g. an SBOM). |
| `app.replicaCount` | `2` | Replicas without autoscaling. |
| `app.readOnlyAppCode` | `true` | Mount the code read-only, except for the writable TYPO3 directories. |
| `app.setup.commands` | `extension:setup`, `cache:warmup` | Run before FrankenPHP starts. |
| `app.setup.lock.enabled` | `true` | Serialise the setup across pods with a database advisory lock. |
| `app.health.path` / `app.health.host` | `/`, `ingress.host` | Startup/readiness probe and `helm test`. |
| `autoscaling.enabled` | `false` | HorizontalPodAutoscaler on CPU (and optionally memory). |
| `podDisruptionBudget.enabled` | `true` | `maxUnavailable: 1`. |
| `ingress.host` / `ingress.className` | — / `""` | Public host name and IngressClass. |
| `database.host` | `""` | Literal host; empty reads `db-host` from the secret. |
| `database.tls.enabled` / `clientCertificate` | `true` / `true` | TLS and mutual TLS to the database. |
| `database.tls.caSecret.name` | `""` | CA of the database server; empty uses the internal CA. |
| `valkey.enabled` / `valkey.tls.enabled` | `true` / `true` | Bundled Valkey, TLS-only with client certificates. |
| `valkey.persistence.enabled` | `false` | Keep the Valkey dataset on a PVC. |
| `secrets.existingSecret` | `""` | Use your own Secret instead of an ExternalSecret. |
| `secrets.externalSecret.secretStoreRef.name` / `remoteKey` | — | Where ESO reads the credentials. |
| `secrets.extra` | `[]` | Additional secrets as files, each with a `<NAME>_FILE` variable. |
| `internalTls.enabled` | `true` | Namespaced CA and certificates via cert-manager. |
| `internalTls.issuer.create` | `true` | `false` plus `issuer.existing` to use a shared issuer. |
| `scheduler.enabled` / `scheduler.schedule` | `true` / `*/5 * * * *` | TYPO3 scheduler CronJob. |
| `backup.enabled` / `backup.target` | `false` / `pvc` | Database dump to a PVC or to S3 (`backup.s3.*`). |
| `networkPolicy.enabled` | `true` | Default deny plus per-component allows. |
| `networkPolicy.ingressController.*` | `ingress-nginx` namespace | Who may reach port 8080. |
| `networkPolicy.database.to` / `registry.to` | any address | Narrow these to your database and registry. |
| `networkPolicy.extraAppEgress` | `[]` | SMTP, object storage and other outbound flows of TYPO3. |

## Security notes

The threat model behind these notes, including the residual risks, is in
[docs/threat-model.md](docs/threat-model.md).

- **Supply chain.** The code runs only after `cosign verify` succeeded against
  your public key. Reference the artefact by digest: cosign verifies the digest
  the tag resolves to, and a tag could move between the verify and the pull
  initContainer. With a digest both see the same bytes. `NOTES.txt` warns when
  a tag is used.
- **Transparency log.** `code.verify.ignoreTlog` defaults to `false`. Set it
  only for private signing setups without Rekor; the signature is still checked.
- **Containers.** Every container, init containers and the test pod included,
  runs as non-root with a read-only root filesystem, no privilege escalation,
  all capabilities dropped and the `RuntimeDefault` seccomp profile. Service
  account tokens are not mounted. The chart passes the `restricted` Pod
  Security Standard.
- **mTLS.** A CA per release (namespace) issues 30-day leaf certificates.
  Valkey requires client certificates and TLS 1.3; a sidecar reloads its
  server certificate after rotation. The TYPO3 pods pick up a rotated client
  certificate on their next connection; with `internalTls.reloaderAnnotations`
  [Stakater Reloader](https://github.com/stakater/Reloader) restarts them
  instead.
- **Database TLS.** With `database.tls.clientCertificate` the database has to
  trust the release CA (`kubectl get secret <release>-typo3-ca`) and should map
  the client certificate subject to the database user (`REQUIRE SUBJECT` in
  MariaDB/MySQL). If the database already has its own PKI, point
  `internalTls.issuer.existing` at a cert-manager issuer of that PKI instead.
  The backup job has its own client certificate, so it can be granted
  read-only rights.
- **Secrets.** Credentials reach the pods as files with mode `0440`, never as
  environment values or in a manifest. The chart only renders a reference to
  your secret backend. Exception: the S3 key pair of the backup, which rclone
  reads from its environment.
- **Network.** The default deny covers the whole namespace — one namespace per
  tenant is assumed. The allows for the database, the registry and the backup
  target default to any address on the respective port only; narrow them to
  your actual peers. Note that some CNIs do not apply `ipBlock` rules to
  in-cluster pod IPs: for a database inside the cluster use a
  `namespaceSelector`/`podSelector` peer.
- **Schema migrations.** `extension:setup` runs in an initContainer of every
  new pod, because it also publishes `public/_assets` into that pod's own code
  volume; a single hook Job could not do that for every replica. To keep a
  fresh install or a scale-up from running the schema work in parallel, the
  setup runs under a database advisory lock (`app.setup.lock`): one pod at a
  time, the others wait. The lock belongs to the connection, so a pod that
  dies mid-setup releases it.

## Files and uploads

The pods are stateless: code arrives from the registry, everything else is in
the database, Valkey or object storage. There is **no ReadWriteMany volume**,
and none should be added — it would couple every replica to one storage system
and make the pods pets again.

`fileadmin` and other user uploads therefore have to live on S3-compatible
object storage, configured as a TYPO3 file storage with a FAL driver for S3.
Setting that up is out of scope for this chart; allow the outbound flow with
`networkPolicy.extraAppEgress`.

`typo3temp/` is per pod. Assets TYPO3 generates on the fly (processed images,
concatenated CSS/JS) are rebuilt on each pod; processed images belong on the
object storage as well.

## Operations

- **Scheduler traffic.** Every scheduler run pulls and verifies the code
  artefact, like a web pod. With a large artefact and a five-minute schedule
  that adds up to a lot of registry traffic; adjust `scheduler.schedule` or
  keep the artefact lean (no dev dependencies, no build caches).
- **Backups.** The dump runs with `--single-transaction` against the configured
  schema and is stored only if it exceeds `backup.minBytes`. A PVC created by
  the chart survives `helm uninstall`. Test restores regularly; a backup that
  was never restored is a hope, not a backup.
- **Upgrades.** A new `code.artifact` changes a pod annotation and rolls the
  Deployment. The scheduler picks it up on its next run.

## Deliberately not included

- A bundled database. Run MariaDB/MySQL with an operator or as a managed service.
- Persistent storage for `fileadmin` (see above).
- Web application firewall, bot protection or rate limiting — that is the job
  of your Ingress layer.
- Monitoring, dashboards and alerting rules.
- Mail delivery. Configure an SMTP relay in TYPO3 and allow it via `extraAppEgress`.
- Namespaces, ResourceQuotas and LimitRanges — create them with the namespace,
  not with the application.
- Image and dependency scanning. The CVE gate runs in CI before the artefact
  is signed; the cluster only checks the signature.
- Any particular cloud provider. Nothing in the chart assumes one.

### Why not an operator?

An operator is custom code that runs with cluster-wide rights and reconciles
state on its own. That is more attack surface and more software to maintain,
and its decisions happen at runtime rather than in a reviewed change. A chart
rendered by a GitOps tool is declarative: every change is a diff that someone
reviewed, and the cluster holds no logic of its own. An operator starts to pay
off only with many tenants whose lifecycle (provisioning databases, rotating
credentials, coordinating upgrades across instances) cannot be expressed
declaratively. For one TYPO3 installation, or a handful, it cannot.

## Development

```bash
helm lint --strict .
for p in minimal full ha; do
  helm template t . -f ci/values-$p.yaml --kube-version 1.31.0 \
    | kubeconform -strict -ignore-missing-schemas -kubernetes-version 1.31.0
done
```

The GitHub Actions in `.github/workflows/` run the same checks on every pull
request, plus `gitleaks` and a REUSE lint, and publish releases from `v*`
tags. [pinup](https://github.com/ohartwig/pinup) keeps the pinned actions,
tools and default images current (`.pinup.yaml`); a pull request that changes
a default image also needs a chart patch release.

## Licence

Apache License 2.0, see [LICENSE](LICENSE). The repository follows the
[REUSE](https://reuse.software) specification; see [REUSE.toml](REUSE.toml).

# Local hermetic image build

Requires Git, Python 3, and a running Podman engine. On macOS, start your
Podman machine first with `podman machine start`.

From the repository root:

```sh
bash deploy/konflux/build-local.sh
```

The script snapshots the current tracked files, prefetches the frontend npm
and backend Go dependencies with Hermeto, and injects the generated environment
into a temporary Dockerfile. It builds with `--network none` for the Podman
engine's native architecture, then runs the executable with `--help`.
Image pulls and dependency prefetch require network access.

The default image tag is `localhost/openshell-dashboard:konflux-local`.
Pass a different tag as the first argument. Set `HERMETO_IMAGE` to choose a
specific fetcher image or `PODMAN` to select a Podman executable or wrapper.
The image's `version` label defaults to the frontend manifest's version.
Override it for a release build with `VERSION=1.2.3 bash deploy/konflux/build-local.sh`.

Source snapshots and prefetched dependencies remain under
`.cache/konflux-build/` for inspection. Hermeto's manifest rewrites affect only
the snapshot. The temporary clone retains the repository's origin; GitHub SSH
origins are converted to HTTPS so the fetcher does not need local SSH keys.

## FIPS requirement

The Konflux image builds with Red Hat Go, `CGO_ENABLED=1`, and
`GOEXPERIMENT=strictfipsruntime`. It links dynamically and uses UBI Minimal's
OpenSSL libraries. Red Hat Go automatically selects the OpenSSL FIPS backend
when the host reports `/proc/sys/crypto/fips_enabled=1`. The image leaves
`GOLANG_FIPS` unset so non-FIPS hosts use the standard crypto backend. The Go
experiment is required for this compiler: `-tags strictfipsruntime` alone does
not select its strict checks. See [Red Hat's Go Toolset guidance](https://developers.redhat.com/articles/2025/01/23/fips-mode-red-hat-go-toolset).

A successful local build or crypto smoke test does not establish FIPS
compliance. Before shipping, validate the final image on FIPS-enabled
RHEL/RHCOS for each supported architecture, confirm the cryptographic module
and platform meet the applicable Red Hat validation requirements, and test
the dashboard's TLS/mTLS gateway connections and HTTPS endpoints in that
environment. Container FIPS mode requires a FIPS-enabled host; see
[Red Hat's container guidance](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/security_hardening/switching-rhel-to-fips-mode_security-hardening).

# envoy-builds

Build/release infrastructure for **Envoy proxy binaries** (`kumahq/envoy-builds`). Compiles Envoy from source for `linux`/`darwin` × `amd64`/`arm64`, plus a FIPS variant (linux/amd64) and a CentOS 7 variant, then publishes them as **draft GitHub releases**. No application code — Bash + Bazel + Docker + Terraform + GitHub Actions glue around the upstream `envoyproxy/envoy` build.

## Tech Stack

- **Bash** — build orchestration in `scripts/` (`set -o errexit/pipefail/nounset`)
- **Python 3** — `scripts/contrib_enabled_matrix.py` (reads envoy's `contrib_build_config.bzl`)
- **Bazel / Bazelisk** — actual compile (`//contrib/exe:envoy-static`)
- **Docker** — hermetic linux/centos builds in the upstream envoy-build image
- **Terraform** (AWS) — provisions Linux EC2 + mac dedicated hosts in `us-east-2`
- **GitHub Actions** — orchestration, matrix, release publishing
- No test suite. "Tests" = the build produces a working `envoy` binary.

## Layout

- `Makefile` — `build/envoy`, `build/envoy/fips`, `clean/envoy`
- `scripts/` — per-OS build scripts, `fetch_sources.sh`, `contrib_enabled_matrix.py`, Dockerfiles
- `patches/` — per-version, per-OS patches (see `.claude/rules/patch-system.md`)
- `terraform/` — AWS build-host provisioning
- `.github/workflows/` — `build-and-release.yaml` (orchestrator), `build.yaml`, `build-github.yaml`, `release-on-schedule.yaml`, `release-hosts.yaml`, `ci.yaml`
- `policy.json` — IAM permissions the `envoy-ci` role must have

## Local Build Commands

```bash
ENVOY_VERSION=1.34.1 make build/envoy        # host OS/arch (NOTE: no leading "v")
make build/envoy                             # ENVOY_VERSION defaults to "main"
ENVOY_VERSION=1.34.1 make build/envoy/fips   # FIPS (linux/amd64 only)
ENVOY_DISTRO=centos ENVOY_VERSION=1.34.1 make build/envoy   # CentOS 7 variant
make clean/envoy                             # clean sources + artifacts
```

- `ENVOY_VERSION` is the primary knob (no `v`). Defaults to `main` (`ENVOY_VERSION ?= main`) → builds `main`; any other value → `ENVOY_TAG=v$ENVOY_VERSION`. The `ENVOY_TAG=...` form in the README is overridden by the Makefile — **use `ENVOY_VERSION`**.
- `GOOS`/`GOARCH` default to the host (`go env`). `SOURCE_DIR` defaults to `$TMPDIR/envoy-sources`. Add `BAZEL_BUILD_EXTRA_OPTIONS` for extra Bazel flags.
- Output: `build/artifacts-$GOOS-$GOARCH/envoy/envoy-v$VERSION[+fips][-centos]`.

## Detailed Rules

- [Version-Gating Map](.claude/rules/version-gating.md) — build behavior gated on Envoy minor version across many files; **check every entry when adding a version**, plus the new-version checklist
- [Patch System](.claude/rules/patch-system.md) — `patches/` naming, how patches are wired in, custom glibc bundling
- [CI Build Paths](.claude/rules/ci-build-paths.md) — linux (AWS EC2) vs darwin (GitHub runner) legs differ; orchestrator + build flow

## Quality Gates

Before committing / opening a PR:

- [ ] Reproduced the build (or failure) **locally** when feasible — native `make build/envoy` on macOS, Docker-based `build_linux.sh`/`build_centos.sh` on Linux.
- [ ] Shell scripts pass `shellcheck` cleanly — fix findings at source, never suppress.
- [ ] Terraform: `terraform -chdir=terraform fmt -check` and `... validate` — **do not** `apply`/`destroy` locally (see Execution Boundaries).
- [ ] GitHub Actions edited? Re-run a representative build via `gh workflow run`.
- [ ] Version-gating maps touched together — grep the minor number across all gating files.
- [ ] New actions pinned to a full commit SHA with a `# vX.Y.Z` comment.

## Common Commands

```bash
terraform -chdir=terraform fmt -check && terraform -chdir=terraform validate
gh workflow run build-and-release.yaml -f version=1.34.1   # full build+release (draft); confirm first
gh workflow run build.yaml        -f os=linux  -f arch=amd64 -f version=1.34.1   # one linux leg
gh workflow run build-github.yaml -f os=darwin -f arch=arm64 -f version=1.34.1   # one darwin leg
gh run watch "$(gh run list -w build-and-release.yaml -L1 --json databaseId -q '.[0].databaseId')"
objdump -T ./envoy | grep GLIBC | sed 's/.*GLIBC_\([.0-9]*\).*/\1/g' | sort -Vu | tail -1   # glibc req
```

## Execution Boundaries

- ✅ **Native darwin build** (`make build/envoy` on a macOS host) — run and verify locally.
- ✅ **Docker linux/centos build** (`build_linux.sh`, `build_centos.sh`) — run locally if Docker is available.
- 🚫 **Terraform `apply`/`destroy`** — CI-only. Provisions **real AWS resources** (EC2, mac dedicated hosts, IAM) under `envoy-ci` in `us-east-2`. Locally limit to `fmt`/`validate`/`plan` (and `plan` only with credentials you were told to use).
- 🚫 **Build/release workflows** — trigger only via `gh workflow run` with **explicit user confirmation**. Never auto-dispatch; mac hosts and draft releases are side-effecting. Don't cancel an in-progress build (Terraform may not clean up).

## Anti-Patterns

- ❌ Leading `v` in `ENVOY_VERSION` / version input — `build-and-release` and `check-input` reject `v*`; use `1.34.1`.
- ❌ Editing one version-gating map and not the siblings (e.g. bumping macOS runner but not LLVM/min-version). Builds fail in confusing ways.
- ❌ `terraform apply`/`destroy` from a laptop, or cancelling a running build — orphans AWS hosts/roles.
- ❌ Enabling extra contrib extensions casually — only `kafka_broker` is intended; the disabled set is deliberate (build time/size, macOS compat).
- ❌ Adding FIPS to darwin or arm64 matrix entries — FIPS is **linux/amd64 only**.
- ❌ Suppressing linter findings (shellcheck/ruff/oxlint ignore) or bypassing hooks (`--no-verify`). Fix the root cause.
- ❌ Bumping an action to a floating tag/branch — pin the full SHA (dependabot manages these).
- ❌ Hand-editing files synced from `kumahq/.github` (`meta_org.yml`, `CONTRIBUTING.md`, `CODEOWNERS`, `lifecycle.yml`) — overwritten upstream.

## Conventions

- **Commits:** Conventional Commits, scope **required** — `type(scope): desc`. Infra uses its own type+scope: `ci(actions): ...`, `build(build): ...`, `chore(deps): ...` (never `feat(ci)`). Title ≤ 50 chars. Sign with `-s -S`.
- **Actions:** pinned to full commit SHA + `# vX.Y.Z` comment; dependabot owns version bumps.
- **AWS:** region `us-east-2`; CI assumes role `envoy-ci`; required permissions tracked in `policy.json` — keep in sync when Terraform needs a new AWS action (the `envoy-ci-test-user` IAM user validates it).

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
- `patches/` — per-version, per-OS patches (see [Patch System](#patch-system))
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

- `ENVOY_VERSION` is the primary knob (no `v`). `main` → builds `main`; any other value → `ENVOY_TAG=v$ENVOY_VERSION`. The `ENVOY_TAG=...` form in the README is overridden by the Makefile — **use `ENVOY_VERSION`**.
- `GOOS`/`GOARCH` default to the host (`go env`). `SOURCE_DIR` defaults to `$TMPDIR/envoy-sources`. Add `BAZEL_BUILD_EXTRA_OPTIONS` for extra Bazel flags.
- Output: `build/artifacts-$GOOS-$GOARCH/envoy/envoy-v$VERSION[+fips][-centos]`.

## Detailed Rules

Build behavior is gated on the Envoy minor version across many files — check every entry when adding a version (see the [Version-Gating Map](#version-gating-map) and its new-version checklist). The [Patch System](#patch-system) covers `patches/` naming, how patches are wired in, and custom glibc bundling. The [CI Build Paths](#ci-build-paths) section explains how the linux (AWS EC2) and darwin (GitHub runner) legs differ, plus the orchestrator + build flow.

### Version-Gating Map

Build behavior is gated on the Envoy **minor** version in multiple files. When adding/fixing a version, check **every** entry — they must stay consistent. Grep the minor number across all gating files; updating one and forgetting siblings causes confusing build failures.

| Gate | File | Behavior |
|------|------|----------|
| FIPS config flag | `Makefile` | `main` or minor ≥ **38** → `--config=boringssl-fips`; else `--define boringssl=fips` |
| Ubuntu Dockerfile patch | `scripts/build_linux.sh` (`patch_per_version`) | Applied for `main`, `v1.37`, `v1.38`; empty for v1.34–v1.36 |
| Darwin Lua patch | `scripts/fetch_sources.sh` (`patches_darwin`) | Applied for v1.33–v1.36; none for v1.37+ |
| Generic source patch | `scripts/fetch_sources.sh` (`patches_per_version`) | Currently all empty — add here if upstream needs a source patch |
| macOS min version | `build-github.yaml`, `build.yaml` | `main`/minor ≥ **34** → `--copt=-mmacos-version-min=13.3 --host_copt=...` |
| macOS runner image | `build-github.yaml` (`select-runner`) | `main`/minor ≥ **35** → `macos-15`; else `macos-14` |
| LLVM@18 (amd64) | `build-github.yaml`, `build.yaml` | `main`/minor ≥ **37** (darwin amd64) → install `llvm@18`, set `BAZEL_LLVM_PATH` |
| Hickory DNS resolver | `build-github.yaml` | `main`/minor ≥ **38** → `--//source/extensions/network/dns_resolver/hickory:enabled=false` (no `@llvm_toolchain_llvm` on macOS) |
| mac dedicated-host AMI | `terraform/macos.tf` | envoy 1.32/1.33/1.34 → macOS 12 AMI; else macOS 14 (legacy AWS path only) |

> The `ci`-variant upstream build images (v1.37+) lack `binutils`/`strip`, so `Dockerfile.build-*` install it and `build_*.sh` append `ci-` to the build tag when the repo isn't `envoy-build-ubuntu`.

#### Adding a New Envoy Version (checklist)

1. Try a **local build first**: `ENVOY_VERSION=<x.y.z> make build/envoy` (native darwin) or via Docker for linux. Reproduce failures locally before touching CI.
2. Walk the table above; add the new `vX.Y` key to every map that needs it (or confirm existing `≥ N` conditions already cover it). Don't update one map and forget the siblings.
3. If upstream needs a source/Dockerfile fix, add a patch under `patches/` and wire it into `patches_per_version` / `patches_darwin` / `patch_per_version` with the **`vX.Y`** key (see [Patch System](#patch-system)).
4. Verify FIPS: if minor ≥ 38, confirm the `--config=boringssl-fips` path builds (linux/amd64).
5. Trigger a real build via `gh workflow run` and confirm all matrix legs are green before releasing.

### Patch System

- Patches live in `patches/`, named `<key>-NNNN-<desc>.patch`.
- **Darwin Lua** patches (`vX.Y-0001-darwin-patch-lua.patch`) are git-applied to envoy sources in `scripts/fetch_sources.sh` for older versions only.
- **Ubuntu Dockerfile** patch (`main-0001-linux-dockerfile-build-ubuntu.patch`) is `patch`-applied to `scripts/Dockerfile.build-ubuntu` in `scripts/build_linux.sh`.
- Version key = `vMAJOR.MINOR` (e.g. `v1.35.8` → `v1.35`). An empty `"$()"` entry means "no patch for this version" — keep the key, leave it empty.

See the [Version-Gating Map](#version-gating-map) for which patch arrays apply per version.

#### Custom glibc Bundling

Envoy needs glibc ≥ 2.30; older OSes (CentOS 7, RHEL 8.8) need a bundled newer glibc + `patchelf` to repoint the interpreter/rpath. Pre-built `glibc-2.37-linux-amd64` and full `patchelf` instructions live in `README.md` — link there rather than duplicating.

### CI Build Paths

The linux and darwin legs use **different** infrastructure — know which one you're touching.

| OS | Workflow | Runs on | Notes |
|----|----------|---------|-------|
| **linux** | `build.yaml` | AWS EC2 VM via Terraform | Generates SSH key, `terraform apply`, SSHes in, runs `make`, `scp`s the binary back, always `terraform destroy`. Assumes IAM role `envoy-ci`. |
| **darwin** | `build-github.yaml` | GitHub-hosted macOS runner | `select-runner` job picks `macos-14`/`macos-15` (+`-large`/`-xlarge`). Installs brew deps incl. `llvm@18`. No Terraform. |

- **`build-and-release.yaml`** is the orchestrator. Matrix: linux `{amd64, amd64+fips, arm64}` via `build.yaml`; darwin `{amd64, arm64}` via `build-github.yaml`. Then `package` tars each binary as `envoy-<os>-<arch>-v<version>[+fips].tar.gz` (renamed to `envoy` inside the archive) and creates a **draft** release `v<version>`.
- **FIPS is linux/amd64 only.** Don't add FIPS to darwin/arm64 matrix entries.
- **`release-on-schedule.yaml`** (daily 00:00) diffs `envoyproxy/envoy` releases from the last 24h against existing `kumahq/envoy-builds` releases and builds any missing ones, `max-parallel: 1`.
- **`build.yaml`'s** macOS dedicated-host path (`find-or-create-host.sh`, `macos.tf`) still exists but darwin release builds now go through GitHub runners. The macOS-dedicated-host limit (~4 parallel) and `release-hosts.yaml` cleanup are legacy of that path.

#### Build Flow (what actually happens)

1. **`make build/envoy`** picks `scripts/build_$(GOOS).sh` (or `build_centos.sh` if `ENVOY_DISTRO=centos`).
2. **`fetch_sources.sh`** clones `envoyproxy/envoy` at `ENVOY_TAG` into `$SOURCE_DIR` (depth 1), then applies any matching patches.
3. **`contrib_enabled_matrix.py`** emits `--<extension>:enabled=true/false` flags — **only `envoy.filters.network.kafka_broker` is enabled**; all other contrib extensions are disabled.
4. **linux/centos**: build inside Docker (`Dockerfile.build-ubuntu`/`-centos`) `FROM` the upstream envoy-build image resolved from envoy's `.github/config.yml` (`repo:`/`tag:`/`sha:`). **darwin**: build natively with `bazel build`.
5. Binary is **stripped** (`strip envoy-static -o envoy`) and copied to `build/artifacts-$GOOS-$GOARCH/envoy/`.

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
- ❌ Bumping an action to a floating tag/branch — pin the full SHA (Renovate/dependabot manages these).
- ❌ Hand-editing files synced from `kumahq/.github` (`meta_org.yml`, `CONTRIBUTING.md`, `CODEOWNERS`, `lifecycle.yml`) — overwritten upstream.

## Conventions

- **Commits:** Conventional Commits, scope **required** — `type(scope): desc`. Infra uses its own type+scope: `ci(actions): ...`, `build(build): ...`, `chore(deps): ...` (never `feat(ci)`). Title ≤ 50 chars. Sign with `-s -S`.
- **Actions:** pinned to full commit SHA + `# vX.Y.Z` comment; Renovate/dependabot owns version bumps.
- **AWS:** region `us-east-2`; CI assumes role `envoy-ci`; required permissions tracked in `policy.json` — keep in sync when Terraform needs a new AWS action (the `envoy-ci-test-user` IAM user validates it).

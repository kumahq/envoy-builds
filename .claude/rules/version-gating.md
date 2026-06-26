# Version-Gating Map

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

## Adding a New Envoy Version (checklist)

1. Try a **local build first**: `ENVOY_VERSION=<x.y.z> make build/envoy` (native darwin) or via Docker for linux. Reproduce failures locally before touching CI.
2. Walk the table above; add the new `vX.Y` key to every map that needs it (or confirm existing `≥ N` conditions already cover it). Don't update one map and forget the siblings.
3. If upstream needs a source/Dockerfile fix, add a patch under `patches/` and wire it into `patches_per_version` / `patches_darwin` / `patch_per_version` with the **`vX.Y`** key (see `patch-system.md`).
4. Verify FIPS: if minor ≥ 38, confirm the `--config=boringssl-fips` path builds (linux/amd64).
5. Trigger a real build via `gh workflow run` and confirm all matrix legs are green before releasing.

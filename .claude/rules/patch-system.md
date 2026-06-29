# Patch System

- Patches live in `patches/`, named `<key>-NNNN-<desc>.patch`.
- **Darwin Lua** patches (`vX.Y-0001-darwin-patch-lua.patch`) are git-applied to envoy sources in `scripts/fetch_sources.sh` for older versions only.
- **Ubuntu Dockerfile** patch (`main-0001-linux-dockerfile-build-ubuntu.patch`) is `patch`-applied to `scripts/Dockerfile.build-ubuntu` in `scripts/build_linux.sh`.
- Version key = `vMAJOR.MINOR` (e.g. `v1.35.8` → `v1.35`). An empty `"$()"` entry means "no patch for this version" — keep the key, leave it empty.

See `version-gating.md` for which patch arrays apply per version.

## Custom glibc Bundling

Envoy needs glibc ≥ 2.30; older OSes (CentOS 7, RHEL 8.8) need a bundled newer glibc + `patchelf` to repoint the interpreter/rpath. Pre-built `glibc-2.37-linux-amd64` and full `patchelf` instructions live in `README.md` — link there rather than duplicating.

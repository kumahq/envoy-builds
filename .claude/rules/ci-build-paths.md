# CI Build Paths

The linux and darwin legs use **different** infrastructure — know which one you're touching.

| OS | Workflow | Runs on | Notes |
|----|----------|---------|-------|
| **linux** | `build.yaml` | AWS EC2 VM via Terraform | Generates SSH key, `terraform apply`, SSHes in, runs `make`, `scp`s the binary back, always `terraform destroy`. Assumes IAM role `envoy-ci`. |
| **darwin** | `build-github.yaml` | GitHub-hosted macOS runner | `select-runner` job picks `macos-14`/`macos-15` (+`-large`/`-xlarge`). Installs brew deps incl. `llvm@18`. No Terraform. |

> `build-github.yaml` is **OS-agnostic**, not darwin-only — its `workflow_dispatch` accepts `os: darwin` or `linux`, and `select-runner` picks `ubuntu-24.04`/`ubuntu-24.04-arm` when `os == linux`. `build-and-release.yaml` is what routes darwin to it; `gh workflow run build-github.yaml -f os=linux ...` also works. The table maps each OS to the workflow the orchestrator uses for it.

- **`build-and-release.yaml`** is the orchestrator. Matrix: linux `{amd64, amd64+fips, arm64}` via `build.yaml`; darwin `{amd64, arm64}` via `build-github.yaml`. Then `package` tars each binary as `envoy-<os>-<arch>-v<version>[+fips].tar.gz` (renamed to `envoy` inside the archive) and creates a **draft** release `v<version>`.
- **FIPS is linux/amd64 only.** Don't add FIPS to darwin/arm64 matrix entries.
- **`release-on-schedule.yaml`** (daily 00:00) diffs `envoyproxy/envoy` releases from the last 24h against existing `kumahq/envoy-builds` releases and builds any missing ones, `max-parallel: 1`.
- **`build.yaml`'s** macOS dedicated-host path (`find-or-create-host.sh`, `macos.tf`) still exists but darwin release builds now go through GitHub runners. The macOS-dedicated-host limit (~4 parallel) is legacy of that path. **`release-hosts.yaml` cleanup is still active** — it runs daily (`cron: 0 10 * * *`, plus `workflow_dispatch`) against the EC2 mac dedicated-host path that `build.yaml` retains, not just on-demand.

## Build Flow (what actually happens)

1. **`make build/envoy`** picks `scripts/build_$(GOOS).sh` (or `build_centos.sh` if `ENVOY_DISTRO=centos`).
2. **`fetch_sources.sh`** clones `envoyproxy/envoy` at `ENVOY_TAG` into `$SOURCE_DIR` (depth 1), then applies any matching patches.
3. **`contrib_enabled_matrix.py`** emits `--<extension>:enabled=true/false` flags — **only `envoy.filters.network.kafka_broker` is enabled**; all other contrib extensions are disabled.
4. **linux/centos**: build inside Docker (`Dockerfile.build-ubuntu`/`-centos`) `FROM` the upstream envoy-build image resolved from envoy's `.github/config.yml` (`repo:`/`tag:`/`sha:`). **darwin**: build natively with `bazel build`.
5. Binary is **stripped** (`strip envoy-static -o envoy`) — **linux/centos only** (done in `Dockerfile.build-ubuntu`/`-centos`); darwin (`build_darwin.sh`) just `cp`s the un-stripped `bazel-bin/contrib/exe/envoy-static` — then copied to `build/artifacts-$GOOS-$GOARCH/envoy/`.

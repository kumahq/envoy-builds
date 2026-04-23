#!/usr/bin/env bash

set -o errexit
set -o pipefail
set -o nounset

echo "Building Envoy for Darwin"

mkdir -p "$(dirname "${BINARY_PATH}")"

SOURCE_DIR="${SOURCE_DIR}" "scripts/fetch_sources.sh"
CONTRIB_ENABLED_MATRIX_SCRIPT=$(realpath "scripts/contrib_enabled_matrix.py")

pushd "${SOURCE_DIR}"

BAZEL_BUILD_EXTRA_OPTIONS=${BAZEL_BUILD_EXTRA_OPTIONS:-""}
read -ra BAZEL_BUILD_EXTRA_OPTIONS <<< "${BAZEL_BUILD_EXTRA_OPTIONS}"
BAZEL_BUILD_OPTIONS=(
    "--curses=no"
    --verbose_failures
    --//contrib/vcl/source:enabled=false
    "--action_env=PATH=/usr/local/bin:/opt/local/bin:/usr/bin:/bin:/opt/homebrew/bin"
    "--define" "wasm=disabled"
    "${BAZEL_BUILD_EXTRA_OPTIONS[@]+"${BAZEL_BUILD_EXTRA_OPTIONS[@]}"}")

if [[ "${GOARCH:-}" == "amd64" ]]; then
    LLVM_PREFIX=$(brew --prefix llvm 2>/dev/null || true)
    if [[ -n "${LLVM_PREFIX}" && -d "${LLVM_PREFIX}" ]]; then
        # toolchains_llvm has no pre-built LLVM 18.x for x86_64-darwin.
        # BAZEL_LLVM_PATH makes envoy_toolchains() set toolchain_roots (skipping the download).
        # The stub repo satisfies the @llvm_toolchain_llvm//:objcopy ref in dynamic_modules.bzl.
        LLVM_STUB_DIR=$(mktemp -d)
        mkdir -p "${LLVM_STUB_DIR}/bin"
        ln -sf "${LLVM_PREFIX}/bin/llvm-objcopy" "${LLVM_STUB_DIR}/bin/llvm-objcopy"
        cat > "${LLVM_STUB_DIR}/BUILD.bazel" <<'EOF'
package(default_visibility = ["//visibility:public"])
filegroup(name = "objcopy", srcs = ["bin/llvm-objcopy"])
EOF
        BAZEL_BUILD_OPTIONS+=(
            "--repo_env=BAZEL_LLVM_PATH=${LLVM_PREFIX}"
            "--override_repository=llvm_toolchain_llvm=${LLVM_STUB_DIR}"
        )
    fi
fi

read -ra CONTRIB_ENABLED_ARGS <<< "$(python3 "${CONTRIB_ENABLED_MATRIX_SCRIPT}")"

rm -rf /usr/local/include/openssl
bazel build "${BAZEL_BUILD_OPTIONS[@]}" -c opt //contrib/exe:envoy-static "${CONTRIB_ENABLED_ARGS[@]}"

popd

cp "${SOURCE_DIR}"/bazel-bin/contrib/exe/envoy-static "${BINARY_PATH}"

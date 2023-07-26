#!/bin/bash

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

read -ra CONTRIB_ENABLED_ARGS <<< "$(python "${CONTRIB_ENABLED_MATRIX_SCRIPT}")"

rm -rf /usr/local/include/openssl
bazel build "${BAZEL_BUILD_OPTIONS[@]}" -c opt //contrib/exe:envoy-static "${CONTRIB_ENABLED_ARGS[@]}"

popd

cp "${SOURCE_DIR}"/bazel-bin/contrib/exe/envoy-static "${BINARY_PATH}"

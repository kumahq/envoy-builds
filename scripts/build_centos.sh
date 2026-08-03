#!/bin/bash

set -o errexit
set -o pipefail
set -o nounset

echo "Building Envoy for CentOS 7"

mkdir -p "$(dirname "${BINARY_PATH}")"

SOURCE_DIR="${SOURCE_DIR}" "scripts/fetch_sources.sh"
CONTRIB_ENABLED_MATRIX_SCRIPT=$(realpath "scripts/contrib_enabled_matrix.py")

BAZEL_BUILD_EXTRA_OPTIONS=${BAZEL_BUILD_EXTRA_OPTIONS:-""}
read -ra BAZEL_BUILD_EXTRA_OPTIONS <<< "${BAZEL_BUILD_EXTRA_OPTIONS}"
BAZEL_BUILD_OPTIONS=(
    "--config=libc++"
    "--verbose_failures"
    "${BAZEL_BUILD_EXTRA_OPTIONS[@]+"${BAZEL_BUILD_EXTRA_OPTIONS[@]}"}")
BUILD_TARGET=${BUILD_TARGET:-"//contrib/exe:envoy-static"}

pushd "${SOURCE_DIR}"
CONTRIB_ENABLED_ARGS=$(python "${CONTRIB_ENABLED_MATRIX_SCRIPT}")
popd

BUILD_CMD=${BUILD_CMD:-"bazel build ${BAZEL_BUILD_OPTIONS[@]} -c opt ${BUILD_TARGET} ${CONTRIB_ENABLED_ARGS} --//source/extensions/transport_sockets/tcp_stats:enabled=false"}

ENVOY_BUILD_CONFIG=$(curl --fail --location --silent https://raw.githubusercontent.com/envoyproxy/envoy/"${ENVOY_TAG}"/.github/config.yml)
ENVOY_BUILD_REPO=$(echo "${ENVOY_BUILD_CONFIG}" | awk '/^  repo:/ {print $2; exit}')
ENVOY_BUILD_TAG=$(echo "${ENVOY_BUILD_CONFIG}" | awk '/^  tag:/ {print $2; exit}')
ENVOY_BUILD_SHA=$(echo "${ENVOY_BUILD_CONFIG}" | awk '/^  sha:/ {print $2; exit}')
# v1.37+ split envoy-build into variants; "ci" is the standard build image.
if [[ "${ENVOY_BUILD_REPO}" != *envoy-build-ubuntu ]]; then
  ENVOY_BUILD_TAG="ci-${ENVOY_BUILD_TAG}"
fi
ENVOY_BUILD_IMAGE="${ENVOY_BUILD_REPO}:${ENVOY_BUILD_TAG}@sha256:${ENVOY_BUILD_SHA}"

# Export only the "binary" stage to the host: tagging the builder would make docker
# export and unpack the whole bazel tree, which needs tens of GB of extra disk.
OUTPUT_DIR=$(mktemp -d)
trap 'rm -rf "${OUTPUT_DIR}"' EXIT

docker build --target binary --output "type=local,dest=${OUTPUT_DIR}" --progress=plain \
  --build-arg ENVOY_BUILD_IMAGE="${ENVOY_BUILD_IMAGE}" \
  --build-arg BUILD_CMD="${BUILD_CMD}" \
  -f scripts/Dockerfile.build-centos "${SOURCE_DIR}"

mv "${OUTPUT_DIR}/envoy" "${BINARY_PATH}"

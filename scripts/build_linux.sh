#!/bin/bash

set -o errexit
set -o pipefail
set -o nounset

echo "Building Envoy for Linux"

BINARY_DIR="$(dirname "${BINARY_PATH}")"
mkdir -p "$BINARY_DIR"

SOURCE_DIR="${SOURCE_DIR}" "scripts/fetch_sources.sh"
CONTRIB_ENABLED_MATRIX_SCRIPT=$(realpath "scripts/contrib_enabled_matrix.py")

BAZEL_BUILD_EXTRA_OPTIONS=${BAZEL_BUILD_EXTRA_OPTIONS:-""}
read -ra BAZEL_BUILD_EXTRA_OPTIONS <<< "${BAZEL_BUILD_EXTRA_OPTIONS}"
BAZEL_BUILD_OPTIONS=(
    "--config=clang"
    "--verbose_failures"
    "--experimental_ui_max_stdouterr_bytes=104857600"
    "${BAZEL_BUILD_EXTRA_OPTIONS[@]+"${BAZEL_BUILD_EXTRA_OPTIONS[@]}"}")
BUILD_TARGET=${BUILD_TARGET:-"//contrib/exe:envoy-static"}

pushd "${SOURCE_DIR}"
CONTRIB_ENABLED_ARGS=$(python "${CONTRIB_ENABLED_MATRIX_SCRIPT}")
popd

BUILD_CMD=${BUILD_CMD:-"bazel build ${BAZEL_BUILD_OPTIONS[@]} -c opt ${BUILD_TARGET} ${CONTRIB_ENABLED_ARGS}"}

ENVOY_BUILD_SHA=$(curl --fail --location --silent https://raw.githubusercontent.com/envoyproxy/envoy/"${ENVOY_TAG}"/.bazelrc | grep envoyproxy/envoy-build-ubuntu | sed -e 's#.*envoyproxy/envoy-build-ubuntu:\(.*\)#\1#'| uniq)
ENVOY_BUILD_IMAGE="envoyproxy/envoy-build-ubuntu:${ENVOY_BUILD_SHA}"
LOCAL_BUILD_IMAGE="envoy-builder:${ENVOY_TAG}"

echo "BUILD_CMD=${BUILD_CMD}"

docker build -t "${LOCAL_BUILD_IMAGE}" --progress=plain \
  --build-arg ENVOY_BUILD_IMAGE="${ENVOY_BUILD_IMAGE}" \
  --build-arg BUILD_CMD="${BUILD_CMD}" \
  -f "scripts/Dockerfile.build-ubuntu" "${SOURCE_DIR}"

# copy out the binary
id=$(docker create "${LOCAL_BUILD_IMAGE}")
docker cp "$id":/envoy-sources/bazel-bin/contrib/exe/envoy "${BINARY_PATH}"
docker rm -v "$id"

# copy glibc, envoy and patch envoy interpreter
if [[ $ARCH == "amd64" && $ARTIFACT_EXT == *"fips-glibc"* ]]; then
  curl --retry 3 -s --fail --location https://github.com/kumahq/envoy-builds/releases/download/v1.27.0/glibc-2.37-linux-amd64.tar.gz | tar -C "$(dirname "${BINARY_PATH}")" -xz
  docker build --platform linux/amd64 -t envoy-builds-patchelf --progress=plain -f "scripts/Dockerfile.patchelf" "${BINARY_DIR}"
  id=$(docker create --platform linux/amd64 envoy-builds-patchelf)
  docker cp "$id":/envoy-alt "${BINARY_DIR}"/envoy-alt
fi

#!/bin/bash

set -o errexit
set -o pipefail
set -o nounset

echo "Building Envoy for Linux"

mkdir -p "$(dirname "${BINARY_PATH}")"

SOURCE_DIR="${SOURCE_DIR}" "scripts/fetch_sources.sh"
CONTRIB_ENABLED_MATRIX_SCRIPT=$(realpath "scripts/contrib_enabled_matrix.py")

# Define Dockerfile patches per OS and version
declare -A patch_per_version
patch_per_version[main]="$(realpath "patches/main-0001-linux-dockerfile-build-ubuntu.patch")"
patch_per_version[v1.34]="$()"
patch_per_version[v1.35]="$()"
patch_per_version[v1.36]="$()"
patch_per_version[v1.37]="$(realpath "patches/main-0001-linux-dockerfile-build-ubuntu.patch")"
patch_per_version[v1.38]="$(realpath "patches/main-0001-linux-dockerfile-build-ubuntu.patch")"
patch_per_version[v1.39]="$(realpath "patches/main-0001-linux-dockerfile-build-ubuntu.patch")"

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

ENVOY_BUILD_CONFIG=$(curl --fail --location --silent https://raw.githubusercontent.com/envoyproxy/envoy/"${ENVOY_TAG}"/.github/config.yml)
ENVOY_BUILD_REPO=$(echo "${ENVOY_BUILD_CONFIG}" | awk '/^  repo:/ {print $2; exit}')
ENVOY_BUILD_TAG=$(echo "${ENVOY_BUILD_CONFIG}" | awk '/^  tag:/ {print $2; exit}')
# v1.37+ split envoy-build into variants; "ci" is the standard build image.
if [[ "${ENVOY_BUILD_REPO}" != *envoy-build-ubuntu ]]; then
  ENVOY_BUILD_TAG="ci-${ENVOY_BUILD_TAG}"
fi
ENVOY_BUILD_IMAGE="${ENVOY_BUILD_REPO}:${ENVOY_BUILD_TAG}"

echo "BUILD_CMD=${BUILD_CMD}"

# Determine version key from ENVOY_TAG for patch lookup
if [[ "${ENVOY_TAG}" == "main" || "${ENVOY_TAG}" == "master" ]]; then
  VERSION_KEY="${ENVOY_TAG}"
else
  # Extract major.minor from version tag (e.g., v1.35.8 -> v1.35)
  IFS=. read -r major minor rest <<< "${ENVOY_TAG}"
  VERSION_KEY="${major}.${minor}"
fi

echo "ENVOY_TAG=${ENVOY_TAG}, VERSION_KEY=${VERSION_KEY}"

echo "Checking for Dockerfile patches"
if [[ -v patch_per_version["${VERSION_KEY}"] ]]; then
  patches=${patch_per_version["${VERSION_KEY}"]}
  if [[ -n "${patches}" ]]; then
    echo "Applying Dockerfile patch for ${VERSION_KEY}"
    patch "scripts/Dockerfile.build-ubuntu" < "${patches}"
  fi
fi

# Export only the "binary" stage to the host: tagging the builder would make docker
# export and unpack the whole bazel tree, which needs tens of GB of extra disk.
OUTPUT_DIR=$(mktemp -d)
trap 'rm -rf "${OUTPUT_DIR}"' EXIT

docker build --target binary --output "type=local,dest=${OUTPUT_DIR}" --progress=plain \
  --build-arg ENVOY_BUILD_IMAGE="${ENVOY_BUILD_IMAGE}" \
  --build-arg BUILD_CMD="${BUILD_CMD}" \
  -f "scripts/Dockerfile.build-ubuntu" "${SOURCE_DIR}"

mv "${OUTPUT_DIR}/envoy" "${BINARY_PATH}"

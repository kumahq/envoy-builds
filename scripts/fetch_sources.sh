#!/usr/bin/env bash

# This script fetches Envoy source code to $SOURCE_DIR
#
# Requires:
# - $SOURCE_DIR, a directory where sources will be placed
# - $ENVOY_TAG, git tag to reference specific revision

set -o errexit
set -o pipefail
set -o nounset

declare -A patches_per_version
patches_per_version[v1.27]="$(realpath "patches/v1.27-0001-dns-don-t-error-if-header-id-is-0.patch")"
patches_per_version[v1.28]="$(realpath "patches/v1.28-0001-dns-don-t-error-if-header-id-is-0.patch")"
patches_per_version[v1.29]="$(realpath "patches/v1.29-0001-dns-don-t-error-if-header-id-is-0.patch")"
patches_per_version[v1.30]="$(realpath "patches/v1.30-0001-dns-don-t-error-if-header-id-is-0.patch")"
patches_per_version[v1.31]="$(realpath "patches/v1.31-0001-dns-don-t-error-if-header-id-is-0.patch")"
patches_per_version[v1.32]="$()"
patches_per_version[v1.33]="$()"
patches_per_version[v1.34]="$()"
patches_per_version[v1.35]="$()"

PATCH_FILES_1_26=(
  "$(realpath "scripts/dns_filter_resolver.h.patch")"
  "$(realpath "scripts/filter_test.cc.patch")"
  "$(realpath "scripts/rbac_filter.cc.patch")"
)

DARWIN_PATCH_FILE=$(realpath "scripts/luajit.patch.patch")

# clone Envoy repo if not exists
if [[ ! -d "${SOURCE_DIR}" ]]; then
  mkdir -p "${SOURCE_DIR}"
  (
    cd "${SOURCE_DIR}"
    git init .
    git remote add origin https://github.com/envoyproxy/envoy.git
  )
else
  echo "Envoy source directory already exists, just fetching"
  pushd "${SOURCE_DIR}" && git fetch --all && popd
fi

pushd "${SOURCE_DIR}"

git fetch origin --depth=1 "${ENVOY_TAG}"
git reset --hard FETCH_HEAD

echo "ENVOY_TAG=${ENVOY_TAG}"

echo "Checking for patches"

if [[ "${ENVOY_TAG}" == "v1.26"* ]]; then
  echo "Applying patches for Envoy 1.26"
  git apply -v "${PATCH_FILES_1_26[@]}"
else
  if [[ "${GOOS}" == "darwin" ]]; then
    echo "Applying patches for Darwin"
    git apply -v "${DARWIN_PATCH_FILE}"
  fi
fi

IFS=. read -r major minor rest <<< "$(cat VERSION.txt)"
patches=${patches_per_version["v${major}.${minor}"]}
# read string into array because lists of lists is too much for bash
if [[ -n "${patches[@]}" ]]; then
  read -ra patches <<< "${patches}"
  git apply -v "${patches[@]}"
fi

popd

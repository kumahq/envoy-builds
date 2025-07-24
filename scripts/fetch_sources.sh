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
patches_per_version[v1.31]="$(realpath "patches/v1.31-0001-dns-don-t-error-if-header-id-is-0.patch")"
patches_per_version[v1.32]="$()"
patches_per_version[v1.33]="$()"
patches_per_version[v1.34]="$()"
patches_per_version[v1.35]="$()"
patches_per_version[v1.36]="$()"

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

if [[ "${GOOS}" == "darwin" ]]; then
  echo "Applying patches for Darwin"
  git apply -v "${DARWIN_PATCH_FILE}"
fi

IFS=. read -r major minor rest <<< "$(cat VERSION.txt)"
patches=${patches_per_version["v${major}.${minor}"]}
# read string into array because lists of lists is too much for bash
if [[ -n "${patches[@]}" ]]; then
  read -ra patches <<< "${patches}"
  git apply -v "${patches[@]}"
fi

popd

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
patches_per_version[v1.33]="$()"
patches_per_version[v1.34]="$()"
patches_per_version[v1.35]="$()"
patches_per_version[v1.36]="$()"
patches_per_version[v1.37]="$()"
patches_per_version[v1.38]="$()"

declare -A patches_darwin
patches_darwin[v1.33]="$(realpath "patches/v1.33-0001-darwin-patch-lua.patch")"
patches_darwin[v1.34]="$(realpath "patches/v1.34-0001-darwin-patch-lua.patch")"
patches_darwin[v1.35]="$(realpath "patches/v1.35-0001-darwin-patch-lua.patch")"
patches_darwin[v1.36]="$(realpath "patches/v1.36-0001-darwin-patch-lua.patch")"
patches_darwin[v1.37]="$()"
patches_darwin[v1.38]="$()"

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

IFS=. read -r major minor rest <<< "$(cat VERSION.txt)"
if [[ "${GOOS}" == "darwin" ]]; then
  patches=${patches_darwin["v${major}.${minor}"]}
  if [[ -n "${patches[@]}" ]]; then
    read -ra patches <<< "${patches}"
    git apply -v "${patches[@]}"
  fi
fi

patches=${patches_per_version["v${major}.${minor}"]}
# read string into array because lists of lists is too much for bash
if [[ -n "${patches[@]}" ]]; then
  read -ra patches <<< "${patches}"
  git apply -v "${patches[@]}"
fi

popd

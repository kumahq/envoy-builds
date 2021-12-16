WORK_DIR ?= .

BUILD_ENVOY_FROM_SOURCES ?= false

# Remember to update pkg/version/compatibility.go
ENVOY_VERSION = $(shell ${WORK_DIR}/tools/version.sh ${ENVOY_TAG})

ARCH=amd64
ENVOY_DISTRO=linux
OS=linux

SOURCE_DIR=build/envoy-sources

# Target 'build/envoy' allows to put Envoy binary under the build/artifacts-$GOOS-$GOARCH/envoy directory.
# Depending on the flag BUILD_ENVOY_FROM_SOURCES this target either fetches Envoy from binary registry or
# builds from sources. It's possible to build binaries for darwin, linux and centos by specifying GOOS
# and ENVOY_DISTRO variables. Envoy version could be specified by ENVOY_TAG that accepts git tag or commit
# hash values.
.PHONY: build/envoy
build/envoy:
	ENVOY_DISTRO=${ENVOY_DISTRO} \
	ENVOY_VERSION=${ENVOY_VERSION} \
	$(MAKE) build/artifacts-${OS}-${ARCH}/envoy/envoy-${ENVOY_VERSION}-${ENVOY_DISTRO}

build/artifacts-${OS}-${ARCH}/envoy/envoy-${ENVOY_VERSION}-${ENVOY_DISTRO}:
	ENVOY_TAG=${ENVOY_TAG} \
	SOURCE_DIR=${SOURCE_DIR} ${WORK_DIR}/tools/fetch_sources.sh && \
	ENVOY_TAG=${ENVOY_TAG} \
	SOURCE_DIR=${SOURCE_DIR} \
	WORK_DIR=${WORK_DIR} \
	BAZEL_BUILD_EXTRA_OPTIONS=${BAZEL_BUILD_EXTRA_OPTIONS} \
	BINARY_PATH=$@ ${WORK_DIR}/tools/build_${ENVOY_DISTRO}.sh

.PHONY: clean/envoy
clean/envoy:
	rm -rf ${SOURCE_DIR}
	rm -rf build/artifacts-${OS}-${ARCH}/envoy/

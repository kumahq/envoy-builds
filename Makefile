GOOS := $(shell go env GOOS)
GOARCH := $(shell go env GOARCH)

BUILD_ENVOY_SCRIPT ?= scripts/build_$(GOOS).sh

ifeq ($(ENVOY_DISTRO),centos)
	ARTIFACT_EXT ?= -centos
	BUILD_ENVOY_SCRIPT = scripts/build_centos.sh
endif

SOURCE_DIR ?= ${TMPDIR}envoy-sources
ifndef TMPDIR
	SOURCE_DIR ?= /tmp/envoy-sources
endif

.PHONY: build/envoy/fips_glibc
build/envoy/fips_glibc:
	BAZEL_BUILD_EXTRA_OPTIONS="${BAZEL_BUILD_EXTRA_OPTIONS} --define boringssl=fips" \
	ARTIFACT_EXT="+fips-glibc-2.37" $(MAKE) build/envoy

.PHONY: build/envoy/fips
build/envoy/fips:
	BAZEL_BUILD_EXTRA_OPTIONS="${BAZEL_BUILD_EXTRA_OPTIONS} --define boringssl=fips" \
	ARTIFACT_EXT="+fips" $(MAKE) build/envoy

.PHONY: build/envoy
build/envoy:
	ENVOY_TAG=v$(ENVOY_VERSION) \
	SOURCE_DIR=${SOURCE_DIR} \
	GOARCH=${GOARCH} \
	GOOS=${GOOS} \
	BAZEL_BUILD_EXTRA_OPTIONS="${BAZEL_BUILD_EXTRA_OPTIONS}" \
	ARCH="${GOARCH}" \
	BINARY_PATH=build/artifacts-${GOOS}-${GOARCH}/envoy/envoy-v${ENVOY_VERSION}$(ARTIFACT_EXT) $(BUILD_ENVOY_SCRIPT)

.PHONY: clean/envoy
clean/envoy:
	rm -rf ${SOURCE_DIR}
	rm -rf build/artifacts-${GOOS}-${GOARCH}/envoy/
	rm -rf build/envoy/

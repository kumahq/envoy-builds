GOOS := $(shell go env GOOS)
GOARCH := $(shell go env GOARCH)
ENVOY_BUILD_TAG := main
BUILD_ENVOY_SCRIPT ?= scripts/build_$(GOOS).sh

ifeq ($(ENVOY_DISTRO),centos)
	ARTIFACT_EXT ?= -centos
	BUILD_ENVOY_SCRIPT = scripts/build_centos.sh
endif

SOURCE_DIR ?= ${TMPDIR}envoy-sources
ifndef TMPDIR
	SOURCE_DIR ?= /tmp/envoy-sources
endif

ifneq ($(ENVOY_VERSION),main)
    ENVOY_BUILD_TAG=v$(ENVOY_VERSION)
endif

FIPS_BAZEL_OPTION := --define boringssl=fips
ifeq ($(ENVOY_VERSION),main)
	FIPS_BAZEL_OPTION := --config=boringssl-fips
endif

.PHONY: build/envoy/fips
build/envoy/fips:
	BAZEL_BUILD_EXTRA_OPTIONS="${BAZEL_BUILD_EXTRA_OPTIONS} $(FIPS_BAZEL_OPTION)" \
	ARTIFACT_EXT="+fips" $(MAKE) build/envoy

.PHONY: build/envoy
build/envoy:
	ENVOY_TAG=$(ENVOY_BUILD_TAG) \
	SOURCE_DIR=${SOURCE_DIR} \
	GOARCH=${GOARCH} \
	GOOS=${GOOS} \
	BAZEL_BUILD_EXTRA_OPTIONS="${BAZEL_BUILD_EXTRA_OPTIONS}" \
	BINARY_PATH=build/artifacts-${GOOS}-${GOARCH}/envoy/envoy-${ENVOY_BUILD_TAG}$(ARTIFACT_EXT) $(BUILD_ENVOY_SCRIPT)

.PHONY: clean/envoy
clean/envoy:
	rm -rf ${SOURCE_DIR}
	rm -rf build/artifacts-${GOOS}-${GOARCH}/envoy/
	rm -rf build/envoy/

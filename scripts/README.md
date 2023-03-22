# Tools for Envoy

The current directory contains tools for building, publishing and fetching Envoy binaries.

There is a new Makefile target `build/envoy` that builds an `envoy` binary in `build/artifacts-$GOOS-$GOARCH/envoy` directory.

### Usage

Set the `ENVOY_TAG` variable to either a commit or tag.

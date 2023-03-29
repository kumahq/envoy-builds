# Tools for Envoy

The current directory contains tools for building Envoy binaries.

There is a new Makefile target `build/envoy` that places an `envoy` binary in `build/artifacts-$GOOS-$GOARCH/envoy` directory.

### Usage

Build the latest supported Envoy binary for your host OS: 

```shell
$ ENVOY_TAG=v1.25.2 make build/envoy
```

### CI

This repository also contains terraform and a Github workflow for building Envoy
in a VM.

### Github workflow

The AWS IAM policy in `policy.json` is sufficient for running the `build.yaml`
Github workflow.

# Tools for Envoy

The current directory contains tools for building Envoy binaries.

There is a new Makefile target `build/envoy` that places an `envoy` binary in `build/artifacts-$GOOS-$GOARCH/envoy` directory.

## Usage

Build the latest supported Envoy binary for your host OS:

```shell
$ ENVOY_TAG=v1.25.2 make build/envoy
```

## CI

This repository also contains terraform and a Github workflow for building Envoy
in a VM.

### Github workflow

Run the `build-and-release.yaml` workflow to build binaries for linux/darwin
amd64/arm64 and additionally a FIPS version for linux/amd64 and publish a _draft
Github release_.

The Windows binary currently needs to be manually built and uploaded to the
release. See [`terraform/README.md`](terraform/README.md) for more information.

#### AWS IAM

The Github workflow assumes the `envoy-ci` role. This role has the
`envoy-ci-workflow` policy attached, which should have the
permissions listed in `policy.json`. The `envoy-ci-test-user` IAM user also has
this policy attached and can be used to ensure the policy has sufficient
permissions to run the terraform.

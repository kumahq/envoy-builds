# Tools for Envoy

The current directory contains tools for building Envoy binaries.

There is a new Makefile target `build/envoy` that places an `envoy` binary in `build/artifacts-$GOOS-$GOARCH/envoy` directory.

## Usage

Build the latest supported Envoy binary for your host OS:

```shell
$ ENVOY_TAG=v1.30.4 make build/envoy
```

## CI

This repository also contains terraform and a Github workflow for building Envoy
in a VM.

### Github workflow

Run the `build-and-release.yaml` workflow with desired version of envoy without leading `v` (`1.29.7`) to build binaries
for linux/darwin amd64/arm64 and additionally a FIPS version for linux/amd64, windows amd64 and publish a _draft
Github release_.

### Limitations

It's only possible to run 4 jobs in parallel due to the number of available macOS hosts.
#### AWS IAM

The Github workflow assumes the `envoy-ci` role. This role has the
`envoy-ci-workflow` policy attached, which should have the
permissions listed in `policy.json`. The `envoy-ci-test-user` IAM user also has
this policy attached and can be used to ensure the policy has sufficient
permissions to run the terraform.

## Bundling with a custom glibc

### Verifying which version of glibc Envoy requires

Run (objdump requires `binutils-multiarch`):

```bash
objdump -T ./envoy | grep GLIBC | sed 's/.*GLIBC_\([.0-9]*\).*/\1/g' | sort -Vu | tail -1
```

in a directory where Envoy binary is located.
This should spit out something like this:

```bash
root@5b91c156c2ac:/tmp/kong-mesh-2.7.9/bin# objdump -T ./envoy | grep GLIBC | sed 's/.*GLIBC_\([.0-9]*\).*/\1/g' | sort -Vu | tail -1
2.30
```

Which means that glibc version `>= 2.30` is required.

### Bundling process

Some OS-es (CentOS 7, RHEL 8.8) have older versions of glibc that won't work with Envoy,
and will result in errors similar to this one:

```bash
./envoy: /lib64/libm.so.6: version `GLIBC_2.29' not found (required by ./envoy)
```

In order to run Envoy on these OSes you need to either upgrade glibc (which is not always possible or convenient)
or build a newer version of glibc manually and patch the Envoy binary to use the newer version.

We pre-built glibc 2.37 for Linux AMD64 and you can download it [here](https://github.com/kumahq/envoy-builds/releases/download/v1.27.0/glibc-2.37-linux-amd64.tar.gz).

Below are instructions on how to run Envoy with a custom glibc:
1. [Download](https://github.com/kumahq/envoy-builds/releases/download/v1.27.0/glibc-2.37-linux-amd64.tar.gz) or [build](https://ftp.gnu.org/gnu/glibc/) glibc yourself (this can also be done using [docker](https://github.com/sgerrand/docker-glibc-builder) as well).
2. Place the Envoy binary next to the "usr" folder and `cd` into it, so running `ls` it looks like this:
```shell
# ls
envoy     readme.md src       usr
```
3. Use `patchelf` to patch the binary (the path is relative, you can use an absolute path if you need to):

3.1. Installed by package manage (e.g. `apt-get install patchelf`)

```shell
patchelf --set-interpreter usr/glibc-compat/lib/ld-linux-x86-64.so.2 --set-rpath usr/glibc-compat/lib/ envoy
```

3.2. Using docker
```shell
docker run -v .:/envoy -w /envoy --platform linux/amd64 -it onedata/patchelf:0.9 --set-interpreter usr/glibc-compat/lib/ld-linux-x86-64.so.2 --set-rpath usr/glibc-compat/lib/ envoy
```

4. Run `envoy` to verify the process

```shell
./envoy --version                                                                                                                                                                                                                           -- INSERT --

./envoy  version: ea9d25e93cef74b023c95ca1a3f79449cdf7fa9a/1.26.3/Modified/RELEASE/BoringSSL
```

5. Run `ldd` to check the patching worked

```shell
ldd ./envoy
        libm.so.6 => usr/glibc-compat/lib/libm.so.6 (0x0000004006ac9000)
        librt.so.1 => usr/glibc-compat/lib/librt.so.1 (0x0000004006ba9000)
        libdl.so.2 => usr/glibc-compat/lib/libdl.so.2 (0x0000004006bae000)
        libpthread.so.0 => usr/glibc-compat/lib/libpthread.so.0 (0x0000004006bb4000)
        libc.so.6 => usr/glibc-compat/lib/libc.so.6 (0x0000004006bb9000)
        usr/glibc-compat/lib/ld-linux-x86-64.so.2 => /lib64/ld-linux-x86-64.so.2 (0x0000004000000000)
```

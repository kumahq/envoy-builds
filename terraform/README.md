# Using terraform to build Envoy

## Windows

### Logging in

Use AWS SSM Session Manager to get access:

```bash
aws ssm start-session --target $(terraform output -raw instance_id)
```

### Building

On the instance run:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
mkdir C:\bazel
powershell Invoke-WebRequest https://github.com/bazelbuild/bazelisk/releases/latest/download/bazelisk-windows-amd64.exe -OutFile C:\bazel\bazel.exe
choco install -y git.portable
C:\tools\git\bin\bash.exe
export PATH=$PATH:/c/bazel
cd /c
git clone https://github.com/envoyproxy/envoy.git
cd envoy
TEMP=C: ./ci/run_envoy_docker.sh './ci/windows_ci_steps.sh'
```

### Retrieving binary

It's not possible to transfer files using SSM Session Manager directly. We can
instead create a new Windows user, connect using RDP, share a directory and
copy the binary into the shared directory.

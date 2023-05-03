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
```

```bash
export PATH=$PATH:/c/bazel
cd /c
git clone https://github.com/envoyproxy/envoy.git
cd envoy
TEMP=C: ./ci/run_envoy_docker.sh './ci/windows_ci_steps.sh'
```

### Retrieving binary

As of version `v1.25.3` with the above instructions, the binary ends up at:

```
C:\envoy-docker-build\tmp\execroot\envoy\bazel-out\x64_windows-opt\bin\source\exe\envoy-static.exe
```

It's not possible to transfer files using SSM Session Manager directly. We can
instead connect via RDP and transfer files.

Let's create a new Windows user:

```powershell
$password = Read-Host -AsSecureString
New-LocalUser -Name "Envoy" -Password $password
Add-LocalGroupMember -Group "Remote Desktop Users" -Member "Envoy"
```

forward a port to the remote RDP using Session Manager:

```
aws ssm start-session --target $(terraform output -raw instance_id) --document-name AWS-StartPortForwardingSession --parameters "localPortNumber=55678,portNumber=3389"
```

and then connect using RDP to the local port `55678` and share a directory. Finally we can copy the binary into the shared directory.

For example, with `remmina`/`freerdp` on Linux we can share the directory
`/home/mike/projects/kuma/build` and copy the file to the host:

```
cp /envoy-docker-build/tmp/execroot/envoy/bazel-out/x64_windows-opt/bin/source/exe/envoy-static.exe //tsclient/_home_mike_projects_kuma_build
```

On MacOS with the official Microsoft RDP client if we check "Redirect folders" and share a folder, it's located at `//tsclient/<Name of folder>`.

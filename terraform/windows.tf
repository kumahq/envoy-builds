data "aws_ssm_parameter" "windows" {
  name = "/aws/service/ami-windows-latest/Windows_Server-2019-English-Core-EKS_Optimized-1.29/image_id"
}

locals {
  windows_user_data = <<EOF
<powershell>
  # Set execution policy and update security protocol (TLS 1.2)
  Set-ExecutionPolicy Bypass -Scope Process -Force
  [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072

  # Install Chocolatey (package manager for windows)
  iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

  # Create directory for Bazel and download Bazelisk
  $bazelDir = 'C:\bazel'
  mkdir $bazelDir -Force
  Invoke-WebRequest -Uri 'https://github.com/bazelbuild/bazelisk/releases/latest/download/bazelisk-windows-amd64.exe' -OutFile "$bazelDir\bazel.exe"

  # Install aws cli
  $command = "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12"
  Invoke-Expression $command
  Invoke-WebRequest -Uri "https://awscli.amazonaws.com/AWSCLIV2.msi" -Outfile C:\AWSCLIV2.msi
  $arguments = "/i `"C:\AWSCLIV2.msi`" /quiet"
  Start-Process msiexec.exe -ArgumentList $arguments -Wait
  $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine")

  # Install Git using Chocolatey
  choco install -y git.portable
  C:\tools\git\bin\git.exe clone https://github.com/envoyproxy/envoy.git C:/envoy
</powershell>
EOF

}

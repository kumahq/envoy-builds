#!/bin/bash
set -e -o pipefail

arch_error="First argument must be 'arm64' or 'amd64'!"

case $1 in
amd64)
    instance_type="mac1.metal"
    ;;
arm64)
    instance_type="mac2.metal"
    ;;
*)
    echo "$arch_error"
    exit 1
esac

export AWS_REGION=us-east-2
hostID=$(aws ec2 describe-hosts \
    --filter \
        Name=tag-key,Values=EnvoyCI \
        Name=instance-type,Values="$instance_type" \
        Name=state,Values=available \
    | jq -r '.Hosts[].HostId'
)
if [[ $hostID == "" ]]; then
    echo "Found no existing host, creating one instead"
    hostID=$(aws ec2 allocate-hosts \
        --quantity 1 \
        --availability-zone us-east-2b \
        --instance-type "$instance_type" \
        --tag-specifications 'ResourceType=dedicated-host,Tags=[{Key=EnvoyCI,Value=true}]' | \
        jq -r .HostIds[0]
    )
fi 
echo "Creating terraform.tfvars with host $hostID"

cat <<EOF > terraform.tfvars
host_id = "$hostID"
EOF

#!/bin/bash
set -e -o pipefail

export AWS_REGION=us-east-2
hostIDs=$(aws ec2 describe-hosts \
    --filter \
        Name=tag-key,Values=EnvoyCI \
        Name=state,Values=available \
    | jq -r '.Hosts[].HostId'
)

arr=(${hostIDs//$'\n'/ })
for value in "${arr[@]}"
do
  aws ec2 release-hosts --host-ids=$value --no-cli-pager
done

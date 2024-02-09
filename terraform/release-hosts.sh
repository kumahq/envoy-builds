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
code=0
for value in "${arr[@]}"
do
  hostCleaned=$(aws ec2 release-hosts --host-ids=$value --no-cli-pager | jq -r '.Unsuccessful == []')
  if [[ hostCleaned != true ]]; then
    code=1
  fi
done

exit $code

#!/usr/bin/env bash

set -e -o pipefail

describeHosts=$(aws ec2 describe-hosts \
    --filter \
        Name=tag-key,Values=EnvoyCI \
        Name=state,Values=available \
    | jq -r '.Hosts[].HostId'
)

mapfile -t hostIDs <<< "${describeHosts}"

exitCode=0
for hostID in "${hostIDs[@]}"; do
    releaseResponse=$(aws ec2 release-hosts --host-ids="${hostID}" --no-cli-pager)
    if ! jq '(.Successful | length == 1) or (.Unsuccessful | length == 1 and .[0].Error.Code == "Client.HostMinAllocationPeriodUnexpired")' <<< "${releaseResponse}" >/dev/null; then
        echo "Unexpected failure with ${hostID}: ${releaseResponse}"
        exitCode=1
    fi
done

exit "${exitCode}"

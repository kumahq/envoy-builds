#!/bin/bash
# we don't want to exit when send-command fails
set +e

instance_id=$1

while true
do
    instance_status=$(aws ec2 describe-instance-status --instance-ids $instance_id --no-cli-pager --query 'InstanceStatuses[0].InstanceStatus.Status' --output text)
    system_status=$(aws ec2 describe-instance-status --instance-ids $instance_id --no-cli-pager --query 'InstanceStatuses[0].SystemStatus.Status' --output text)
    if [[ $instance_status == ok && $system_status == ok ]]; then
    break
    fi
    echo "Instance not healthy, waiting..."
    sleep 5
done
echo "Instance healthy!"
while true; do
    # check if SSM manager is ready for commands
    # we don't use *aws ssm wait* because there is no way to extend timeout and it fails after 100 seconds
    command_id=$(aws ssm send-command \
    --instance-id $instance_id \
    --document-name "AWS-RunPowerShellScript" \
    --parameters commands="'echo test'" \
    --no-cli-pager \
    --query 'Command.CommandId' \
    --output text)
    if [ $? == 0 ]; then
        break
    fi
    echo "SSM Manager not ready, waiting..."
    sleep 5
done
echo "SSM Manager ready!"

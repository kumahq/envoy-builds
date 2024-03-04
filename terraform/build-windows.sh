#!/bin/bash
instance_id=$1
version=$2
if [[ $version != main ]]; then
    version=v$version
fi

wait_for_command(){
    command_id=$1
    while true; do
        status=$(aws ssm get-command-invocation --instance-id $instance_id --command-id $command_id --query 'Status' --no-cli-pager --output text)
        if [[ "$status" == 'Success' ]]; then
            break
        fi
        sleep 5
    done
}

check_build_status(){
    command_id=$1
    # check if it's success
    aws s3 cp s3://envoy-windows-binary/envoy-build-logs-$version/$command_id/$instance_id/awsrunPowerShellScript/0.awsrunPowerShellScript/stderr .
    if grep -iqF "Build completed successfully" stderr
    then
        echo "Build completed successfully"
    else
        cat stderr
        exit 1
    fi
}

# execute Envoy build command
command_id=$(aws ssm send-command \
    --instance-id $instance_id \
    --document-name "AWS-RunPowerShellScript" \
    --parameters commands="'cd C:/envoy; C:\tools\git\bin\git.exe checkout $version; C:\tools\git\bin\bash.exe -c \\'TEMP=C: /c/envoy/ci/run_envoy_docker.sh ./ci/windows_ci_steps.sh //source/exe:envoy-static\\''" \
    --no-cli-pager \
    --query 'Command.CommandId' \
    --output text \
    --output-s3-bucket-name "envoy-windows-binary" --output-s3-key-prefix "envoy-build-logs-$version")
echo $command_id  
wait_for_command $command_id
check_build_status $command_id

# rename binary file
command_id=$(aws ssm send-command \
    --instance-id $instance_id \
    --document-name "AWS-RunPowerShellScript" \
    --parameters commands="'mv C:\envoy-docker-build\envoy\envoy_binary.tar.gz C:\envoy-docker-build\envoy\envoy_binary_$version.tar.gz'" \
    --no-cli-pager \
    --query 'Command.CommandId' \
    --output text)
echo $command_id  
wait_for_command $command_id

# upload file to s3
command_id=$(aws ssm send-command \
    --instance-id $instance_id \
    --document-name "AWS-RunPowerShellScript" \
    --parameters commands="'aws s3 cp C:\envoy-docker-build\envoy\envoy_binary_$version.tar.gz s3://envoy-windows-binary'" \
    --no-cli-pager \
    --query 'Command.CommandId' \
    --output text)
echo $command_id
wait_for_command $command_id

echo "Binary uploaded to s3"

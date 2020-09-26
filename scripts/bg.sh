#!/bin/bash
#
# Copyright 2014 Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License").
# You may not use this file except in compliance with the License.
# A copy of the License is located at
#
#  http://aws.amazon.com/apache2.0
#
# or in the "license" file accompanying this file. This file is distributed
# on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either
# express or implied. See the License for the specific language governing
# permissions and limitations under the License.

# TARGET_LIST defines which target groups behind Load Balancer this instance should be part of.
# The elements in TARGET_LIST should be seperated by space.
TARGET_GROUP_LIST=""

# PORT defines which port the application is running at.
# If PORT is not specified, the script will use the default port set in target groups
PORT=""

# Under normal circumstances, you shouldn't need to change anything below this line.
# -----------------------------------------------------------------------------

export PATH="$PATH:/usr/bin:/usr/local/bin"

get_instance_id() {
    curl -s http://169.254.169.254/latest/meta-data/instance-id
    return $?
}

INSTANCE_ID=$(get_instance_id)
echo $INSTANCE_ID

ELB_NAME=YourELBName

exec_with_fulljitter_retry() {
    local MAX_RETRIES=${EXPBACKOFF_MAX_RETRIES:-8} # Max number of retries
    local BASE=${EXPBACKOFF_BASE:-2} # Base value for backoff calculation
    local MAX=${EXPBACKOFF_MAX:-120} # Max value for backoff calculation
    local FAILURES=0
    local RESP

    # Perform initial jitter sleep if enabled
    if [ "$INITIAL_JITTER" = "true" ]; then
      local SECONDS=$(( $RANDOM % ( ($BASE * 2) ** 2 ) ))
      sleep $SECONDS
    fi

    # Execute Provided Command
    RESP=$(eval $@)
    until [ $? -eq 0 ]; do
        FAILURES=$(( $FAILURES + 1 ))
        if (( $FAILURES > $MAX_RETRIES )); then
            echo "$@" >&2
            echo " * Failed, max retries exceeded" >&2
            return 1
        else
            local SECONDS=$(( $RANDOM % ( ($BASE * 2) ** $FAILURES ) ))
            if (( $SECONDS > $MAX )); then
                SECONDS=$MAX
            fi

            echo "$@" >&2
            echo " * $FAILURES failure(s), retrying in $SECONDS second(s)" >&2
            sleep $SECONDS

            # Re-Execute provided command
            RESP=$(eval $@)
        fi
    done

    # Echo out CLI response which is captured by calling function
    echo $RESP
    return 0
}

get_instance_region() {
    if [ -z "$AWS_REGION" ]; then
        AWS_REGION=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document \
            | grep -i region \
            | awk -F\" '{print $4}')
    fi

    echo $AWS_REGION
}

AWS_CLI="exec_with_fulljitter_retry aws --region $(get_instance_region)"

autoscaling_group_name() {
    local instance_id=$1
    
    # This operates under the assumption that instances are only ever part of a single ASG.
    local autoscaling_name=$($AWS_CLI autoscaling describe-auto-scaling-instances \
        --instance-ids $instance_id \
        --output text \
        --query AutoScalingInstances[0].AutoScalingGroupName)
    
    if [ $? != 0 ]; then
        return 1
    elif [ "$autoscaling_name" == "None" ]; then
        echo ""
    else
        echo "${autoscaling_name}"
    fi

    return 0
}

asg=$(autoscaling_group_name $INSTANCE_ID)

echo $asg

#Attaching the ELB to the new(Green) ASG created by Codedeploy.

$AWS_CLI autoscaling attach-load-balancers --auto-scaling-group-name $asg --load-balancer-names $ELB_NAME

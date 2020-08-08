#!/bin/bash
INSTANCE_ID=`curl http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null`
REGION=`curl -s http://169.254.169.254/latest/dynamic/instance-identity/document 2>/dev/null | jq -r .region`
ASG=`aws ec2 describe-tags --filters "Name=resource-id,Values=$INSTANCE_ID" --region $REGION --output json | jq -r '.[][] | select(.Key=="aws:autoscaling:groupName") | .Value'`
echo "$ASG"

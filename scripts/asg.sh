INSTANCE_ID=`curl http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null`
REGION=`curl -s http://169.254.169.254/latest/dynamic/instance-identity/document 2>/dev/null | jq -r .region`
ASG=`aws ec2 describe-tags --filters "Name=resource-id,Values=$INSTANCE_ID" --region $REGION --output json | jq -r '.[][] | select(.Key=="aws:autoscaling:groupName") | .Value'`
echo "$ASG"
aws cloudwatch put-metric-alarm --alarm-name "$ASG-alarm" --alarm-description "Alarm for New ASG" --namespace "AWS/EC2" --metric-name CPUUtilization --statistic Average --period 60 --evaluation-periods 3 --threshold 1 --comparison-operator GreaterThanOrEqualToThreshold --dimensions Name=AutoScalingGroupName,Value=$ASG --alarm-actions arn:aws:sns:ap-south-1:272842187865:test-perm --region $REGION

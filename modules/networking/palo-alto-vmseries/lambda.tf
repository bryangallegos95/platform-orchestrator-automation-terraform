# modules/networking/palo-alto-vmseries/lambda.tf
#
# Lambda function for ASG lifecycle management:
#   - On LAUNCH: Attach eth1 (mgmt ENI), disable source_dest_check on eth0
#   - On TERMINATE: Detach ENIs, optionally delicense via SCM
#
# This Lambda is triggered by EventBridge rules on ASG lifecycle events.

# ── Lambda IAM Role ───────────────────────────────────────────────────────────

resource "aws_iam_role" "lambda" {
  name_prefix = "${var.name_prefix}-lambda-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-lambda-role"
  })
}

resource "aws_iam_role_policy" "lambda_ec2" {
  name_prefix = "lambda-ec2-"
  role        = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DeleteNetworkInterface",
          "ec2:AttachNetworkInterface",
          "ec2:DetachNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeInstances",
          "ec2:DescribeSubnets",
          "ec2:ModifyNetworkInterfaceAttribute"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "autoscaling:CompleteLifecycleAction",
          "autoscaling:DescribeAutoScalingGroups"
        ]
        Resource = "*"
      }
    ]
  })
}


resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ── Lambda Function (inline Python) ──────────────────────────────────────────

data "archive_file" "lifecycle_lambda" {
  type        = "zip"
  output_path = "${path.module}/lambda_lifecycle.zip"

  source {
    filename = "index.py"
    content  = <<-PYTHON
import json
import boto3
import os
import time

ec2 = boto3.client('ec2')
asg_client = boto3.client('autoscaling')

MGMT_SUBNET_IDS = json.loads(os.environ['MGMT_SUBNET_IDS'])
MGMT_SG_ID = os.environ['MGMT_SG_ID']

def handler(event, context):
    print(json.dumps(event))
    detail = event.get('detail', {})
    lifecycle_hook = detail.get('LifecycleHookName', '')
    instance_id = detail.get('EC2InstanceId', '')
    asg_name = detail.get('AutoScalingGroupName', '')
    transition = detail.get('LifecycleTransition', '')

    try:
        if transition == 'autoscaling:EC2_INSTANCE_LAUNCHING':
            handle_launch(instance_id)
        elif transition == 'autoscaling:EC2_INSTANCE_TERMINATING':
            handle_terminate(instance_id)

        asg_client.complete_lifecycle_action(
            AutoScalingGroupName=asg_name,
            LifecycleHookName=lifecycle_hook,
            InstanceId=instance_id,
            LifecycleActionResult='CONTINUE'
        )
    except Exception as e:
        print(f"Error: {e}")
        asg_client.complete_lifecycle_action(
            AutoScalingGroupName=asg_name,
            LifecycleHookName=lifecycle_hook,
            InstanceId=instance_id,
            LifecycleActionResult='ABANDON'
        )
        raise

def handle_launch(instance_id):
    """Attach mgmt ENI (eth1) and disable source_dest_check on eth0."""
    # Wait for instance to be running
    waiter = ec2.get_waiter('instance_running')
    waiter.wait(InstanceIds=[instance_id])

    # Get instance details to find AZ and eth0
    response = ec2.describe_instances(InstanceIds=[instance_id])
    instance = response['Reservations'][0]['Instances'][0]
    az = instance['Placement']['AvailabilityZone']
    eth0_id = instance['NetworkInterfaces'][0]['NetworkInterfaceId']

    # Disable source_dest_check on eth0 (data-plane)
    ec2.modify_network_interface_attribute(
        NetworkInterfaceId=eth0_id,
        SourceDestCheck={'Value': False}
    )
    print(f"Disabled source_dest_check on {eth0_id}")

    # Find the mgmt subnet in the same AZ
    mgmt_subnet = None
    for subnet_id in MGMT_SUBNET_IDS:
        subnet_info = ec2.describe_subnets(SubnetIds=[subnet_id])
        if subnet_info['Subnets'][0]['AvailabilityZone'] == az:
            mgmt_subnet = subnet_id
            break

    if not mgmt_subnet:
        raise Exception(f"No mgmt subnet found in AZ {az}")

    # Create mgmt ENI
    eni_response = ec2.create_network_interface(
        SubnetId=mgmt_subnet,
        Groups=[MGMT_SG_ID],
        Description=f"PA mgmt ENI for {instance_id}",
        TagSpecifications=[{
            'ResourceType': 'network-interface',
            'Tags': [
                {'Key': 'Name', 'Value': f'pa-mgmt-{instance_id}'},
                {'Key': 'ManagedBy', 'Value': 'palo-alto-lambda'}
            ]
        }]
    )
    mgmt_eni_id = eni_response['NetworkInterface']['NetworkInterfaceId']
    print(f"Created mgmt ENI: {mgmt_eni_id}")

    # Attach as eth1
    ec2.attach_network_interface(
        NetworkInterfaceId=mgmt_eni_id,
        InstanceId=instance_id,
        DeviceIndex=1
    )
    print(f"Attached {mgmt_eni_id} to {instance_id} as eth1")

def handle_terminate(instance_id):
    """Detach and delete mgmt ENI on termination."""
    response = ec2.describe_network_interfaces(
        Filters=[
            {'Name': 'attachment.instance-id', 'Values': [instance_id]},
            {'Name': 'tag:ManagedBy', 'Values': ['palo-alto-lambda']}
        ]
    )
    for eni in response['NetworkInterfaces']:
        eni_id = eni['NetworkInterfaceId']
        attachment_id = eni.get('Attachment', {}).get('AttachmentId')
        if attachment_id:
            ec2.detach_network_interface(
                AttachmentId=attachment_id, Force=True
            )
            time.sleep(5)
        ec2.delete_network_interface(NetworkInterfaceId=eni_id)
        print(f"Deleted mgmt ENI: {eni_id}")
    PYTHON
  }
}

resource "aws_lambda_function" "lifecycle" {
  function_name    = "${var.name_prefix}-lifecycle"
  role             = aws_iam_role.lambda.arn
  handler          = "index.handler"
  runtime          = "python3.12"
  timeout          = 300
  memory_size      = 128
  filename         = data.archive_file.lifecycle_lambda.output_path
  source_code_hash = data.archive_file.lifecycle_lambda.output_base64sha256

  environment {
    variables = {
      MGMT_SUBNET_IDS = jsonencode([for s in aws_subnet.mgmt : s.id])
      MGMT_SG_ID      = aws_security_group.mgmt.id
    }
  }

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-lifecycle-lambda"
  })
}


# ── EventBridge Rules (trigger Lambda on ASG lifecycle events) ─────────────────

resource "aws_cloudwatch_event_rule" "asg_lifecycle" {
  name_prefix = "${var.name_prefix}-lc-"
  description = "Trigger Lambda on PA ASG lifecycle events"

  event_pattern = jsonencode({
    source      = ["aws.autoscaling"]
    detail-type = ["EC2 Instance-launch Lifecycle Action", "EC2 Instance-terminate Lifecycle Action"]
    detail = {
      AutoScalingGroupName = [aws_autoscaling_group.vmseries.name]
    }
  })

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-lifecycle-rule"
  })
}

resource "aws_cloudwatch_event_target" "lambda" {
  rule = aws_cloudwatch_event_rule.asg_lifecycle.name
  arn  = aws_lambda_function.lifecycle.arn
}

resource "aws_lambda_permission" "eventbridge" {
  statement_id  = "AllowEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lifecycle.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.asg_lifecycle.arn
}

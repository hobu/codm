
resource "aws_launch_template" "launch_template" {
  name = "${var.prefix}-launch-template"

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "${var.prefix}-launch-template"
    }
  }

  user_data = filebase64("${path.module}/userdata.sh")
}


resource "aws_cloudwatch_log_group" "batch_logs" {
    name = "${var.prefix}-${var.stage}-codm-batch"
    retention_in_days = 30
}

resource "aws_batch_compute_environment" "batch-compute-environment" {
    compute_environment_name    = "${var.prefix}-${var.stage}-computeenvironment"
    service_role                = aws_iam_role.batch-service-role.arn
    state                       = "ENABLED"
    type                        = "MANAGED"
    # add compute_resources
    compute_resources {
        instance_type = [  "g6.8xlarge", "g6.16xlarge" ]
        subnets = [ for s in aws_subnet.worker-subnets: s.id ]
        type = "SPOT"
        max_vcpus = 128
        min_vcpus = 0
        ec2_configuration  {
             image_type =  "ECS_AL2023"
        }

        launch_template {
            launch_template_id = aws_launch_template.launch_template.id
        }
        ec2_key_pair = "grid-dev-us-west-2"
        bid_percentage = 100
        image_id = jsondecode(data.aws_ssm_parameter.ami.value).image_id
        spot_iam_fleet_role = aws_iam_role.batch-spot-fleet-role.arn
        instance_role = aws_iam_instance_profile.batch-instance-profile.arn
        security_group_ids = [ aws_security_group.worker-security-group.id ]
    }
    depends_on                  = [ aws_iam_role_policy_attachment.service-attach-1 ]
}

# Add more job queues as we progress in the creation of resources. Should
# probably have a small medium large queue. Don't think we need different sizes
# of instances for them though. Just different priority.
resource "aws_batch_job_queue" "batch-job-queue" {
    name                    = "${var.prefix}-${var.stage}-jobqueue"
    priority                = 1
    state                   = "ENABLED"
    compute_environments    = [ aws_batch_compute_environment.batch-compute-environment.arn ]
    depends_on              = [ aws_batch_compute_environment.batch-compute-environment ]
    tags = {
          Name = "${var.prefix}:sqs.${var.stage}.jobqueue"
          name = "${var.prefix}"
          STAGE = "${var.stage}"
    }
}

# This will change at job submission time
resource "aws_batch_job_definition" "batch-job-definition" {
    name = "${var.prefix}-${var.stage}-job"
    retry_strategy {
        attempts = 1
    }
    timeout {
        attempt_duration_seconds = 7200
    }
    type                 = "container"
    container_properties = jsonencode({
        Image = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com/${var.prefix}-${var.stage}-codm:latest"
        Memory = 96000
        Privileged = true
        Vcpus = 32
        ResourceRequirements = [
            {
                type = "GPU"
                value = "1"
            }
        ]
        Command = [
            "sh",
            "-c",
            "/entry.sh",
            "Ref::bucketname",
            "Ref::collectname",
            "Ref::outputname"
        ]
        Environment = [
            {
                name = "S3_NAME"
                value = aws_s3_bucket.storage.id
            },
            {
                name = "AWS_REGION"
                value = data.aws_region.current.name
            }
        ]
        Privileged = true
        MountPoints = [{
            ContainerPath = "/local",
            ReadOnly = false,
            SourceVolume = "local"
        }]
        Volumes = [{
            Name = "local",
            Host = {
                SourcePath = "/local"
            }
        }]
        LogConfiguration = {
            LogDriver = "awslogs",
            Options = {
                "awslogs-group" = "${var.prefix}-${var.stage}-codm-batch",
                "awslogs-region" = "${data.aws_region.current.name}"
            }
        }



    })
    depends_on           = [ aws_iam_role.batch-job-role , data.aws_ecr_image.batch_ecr_image]
}


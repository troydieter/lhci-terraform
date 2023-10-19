data "aws_availability_zones" "available" {}

resource "random_id" "rando" {
  byte_length = 2
}

locals {
  region = "us-east-1"
  name   = "lhci_terraform-${random_id.rando.hex}"

  vpc_cidr = "172.16.16.0/23"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  container_name = "lhci-${random_id.rando.hex}"
  container_port = 9001

  tags = {
    Name       = local.name
    Project    = "LHCI_terraform"
    Repository = "https://github.com/troydieter/lhci-terraform"
  }
}

data "aws_ssm_parameter" "ecs_optimized_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2/recommended"
}

################################################################################
# Cluster and service
################################################################################

module "ecs_cluster" {
  source  = "terraform-aws-modules/ecs/aws"
  version = "5.2.2"

  cluster_name = local.name
  tags         = local.tags

  services = {
    ecsdemo-frontend = {
      cpu    = 512
      memory = 1024

      # Container definition(s)
      container_definitions = {

        ecs-sample = {
          cpu       = 512
          memory    = 1024
          essential = true
          image     = "patrickhulce/lhci-server:latest"
          port_mappings = [
            {
              name          = "lhci-${random_id.rando.hex}"
              containerPort = 9001
              protocol      = "tcp"
            }
          ]

          readonly_root_filesystem  = false
          enable_cloudwatch_logging = false
        }
      }

      # Capacity provider - autoscaling groups
      default_capacity_provider_use_fargate = false
      autoscaling_capacity_providers = {
        # On-demand instances
        lhci-1 = {
          auto_scaling_group_arn         = module.autoscaling["lhci-1"].autoscaling_group_arn
          managed_termination_protection = "ENABLED"

          managed_scaling = {
            maximum_scaling_step_size = 2
            minimum_scaling_step_size = 1
            status                    = "ENABLED"
            target_capacity           = 60
          }

          default_capacity_provider_strategy = {
            weight = 60
            base   = 20
          }
        }
      }

      #   load_balancer = {
      #     service = {
      #       target_group_arn = "arn:aws:elasticloadbalancing:eu-west-1:1234567890:targetgroup/bluegreentarget1/209a844cd01825a4"
      #       container_name   = "ecs-sample"
      #       container_port   = 80
      #     }
      #   }

      #   subnet_ids = ["subnet-abcde012", "subnet-bcde012a", "subnet-fghi345a"]
      #   security_group_rules = {
      #     alb_ingress_3000 = {
      #       type                     = "ingress"
      #       from_port                = 80
      #       to_port                  = 80
      #       protocol                 = "tcp"
      #       description              = "Service port"
      #       source_security_group_id = "sg-12345678"
      #     }
      #     egress_all = {
      #       type        = "egress"
      #       from_port   = 0
      #       to_port     = 0
      #       protocol    = "-1"
      #       cidr_blocks = ["0.0.0.0/0"]
      #     }
      #   }
    }
  }
}

module "autoscaling" {
  source  = "terraform-aws-modules/autoscaling/aws"
  version = "~> 6.5"
  for_each = {
    # On-demand instances
    lhci-1 = {
      instance_type              = "t3.small"
      use_mixed_instances_policy = false
      mixed_instances_policy     = {}
      user_data                  = <<-EOT
        #!/bin/bash
        cat <<'EOF' >> /etc/ecs/ecs.config
        ECS_CLUSTER=${local.name}
        ECS_LOGLEVEL=debug
        ECS_CONTAINER_INSTANCE_TAGS=${jsonencode(local.tags)}
        ECS_ENABLE_TASK_IAM_ROLE=true
        EOF
      EOT
    }
  }
  name = "${local.name}-${each.key}"

  image_id      = jsondecode(data.aws_ssm_parameter.ecs_optimized_ami.value)["image_id"]
  instance_type = each.value.instance_type

  security_groups                 = [module.autoscaling_sg.security_group_id]
  user_data                       = base64encode(each.value.user_data)
  ignore_desired_capacity_changes = true

  create_iam_instance_profile = true
  iam_role_name               = local.name
  iam_role_description        = "ECS role for ${local.name}"
  iam_role_policies = {
    AmazonEC2ContainerServiceforEC2Role = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
    AmazonSSMManagedInstanceCore        = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  vpc_zone_identifier = module.vpc.private_subnets
  health_check_type   = "EC2"
  min_size            = 1
  max_size            = 2
  desired_capacity    = 1

  # https://github.com/hashicorp/terraform-provider-aws/issues/12582
  autoscaling_group_tags = {
    AmazonECSManaged = true
  }

  # Required for  managed_termination_protection = "ENABLED"
  protect_from_scale_in = true

  # Spot instances
  use_mixed_instances_policy = each.value.use_mixed_instances_policy
  mixed_instances_policy     = each.value.mixed_instances_policy

  tags = local.tags
}


module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 48)]

  enable_nat_gateway = true
  single_nat_gateway = true

  tags = local.tags
}
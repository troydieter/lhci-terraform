data "aws_availability_zones" "available" {}

resource "random_id" "rando" {
  byte_length = 2
}

locals {
  region = "us-east-1"
  name   = "lhci-terraform-${random_id.rando.hex}"

  vpc_cidr = "172.16.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  container_name = "lhci-${random_id.rando.hex}"
  container_port = 9001

  tags = {
    Name       = local.name
    Project    = "LHCI_terraform"
    Repository = "https://github.com/troydieter/lhci-terraform"
  }
}

################################################################################
# Cluster
################################################################################

module "ecs_cluster" {
  source  = "terraform-aws-modules/ecs/aws//modules/cluster"
  version = "5.9.0"

  cluster_name = local.name

  # Capacity provider
  fargate_capacity_providers = {
    FARGATE = {
      default_capacity_provider_strategy = {
        weight = 50
        base   = 20
      }
    }
    FARGATE_SPOT = {
      default_capacity_provider_strategy = {
        weight = 50
      }
    }
  }

  tags = local.tags
}

################################################################################
# Service
################################################################################

module "ecs_service" {
  source     = "terraform-aws-modules/ecs/aws//modules/service"
  version    = "5.9.0"
  depends_on = [module.ecs_cluster]

  name        = local.name
  cluster_arn = module.ecs_cluster.arn

  cpu    = 512
  memory = 1024
  volume = {
    data-vol = {
      efs_volume_configuration = {
        file_system_id     = module.efs.id
        root_directory     = ""
        transit_encryption = "DISABLED"
      }
    }
  }

  container_definitions = {
    "lhci" = {
      name      = local.name
      service   = local.name
      cpu       = 512
      memory    = 1024
      essential = true
      image     = "patrickhulce/lhci-server:latest"
      mount_points = [
        {
          sourceVolume  = "data-vol"
          containerPath = "/data"
        }
      ]
      port_mappings = [
        {
          name          = local.name
          containerPort = local.container_port
          hostPort      = local.container_port
          protocol      = "tcp"
        }
      ]

      # Example image used requires access to write to root filesystem
      readonly_root_filesystem = false
      memory_reservation       = 100
    }
  }

  create_tasks_iam_role = true

  load_balancer = {
    service = {
      target_group_arn = element(module.alb.target_group_arns, 0)
      container_name   = local.name
      container_port   = local.container_port
    }
  }

  subnet_ids = module.vpc.private_subnets
  security_group_rules = {
    alb_ingress_9001 = {
      type                     = "ingress"
      from_port                = local.container_port
      to_port                  = local.container_port
      protocol                 = "tcp"
      description              = "Service port"
      source_security_group_id = module.alb_sg.security_group_id
    }
    alb_ingress_2049 = {
      type                     = "ingress"
      from_port                = "2049"
      to_port                  = "2049"
      protocol                 = "tcp"
      description              = "NFS port"
      cidr_blocks              = [module.vpc.vpc_cidr_block]
    }
    egress_all = {
      type        = "egress"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  tags           = local.tags
  propagate_tags = "TASK_DEFINITION"
}
module "efs" {
  source = "terraform-aws-modules/efs/aws"

  # File system
  name      = "efs-${local.name}"
  encrypted = true

  lifecycle_policy = {
    transition_to_ia = "AFTER_30_DAYS"
  }

  # File system policy
  attach_policy                      = true
  bypass_policy_lockout_safety_check = false

  # Mount targets / security group
  mount_targets = {
    "${local.region}a" = {
      subnet_id = module.vpc.private_subnets[0]
    }
    "${local.region}b" = {
      subnet_id = module.vpc.private_subnets[1]
    }
    "${local.region}c" = {
      subnet_id = module.vpc.private_subnets[2]
    }
  }
  security_group_description = "EFS SG for ${random_id.rando.hex}"
  security_group_vpc_id      = module.vpc.vpc_id
  security_group_rules = {
    vpc = {
      # relying on the defaults provdied for EFS/NFS (2049/TCP + ingress)
      description = "NFS ingress from VPC private subnets"
      cidr_blocks = [module.vpc.vpc_cidr_block]
    }
  }

  # Backup policy
  enable_backup_policy = false

  tags = local.tags
}
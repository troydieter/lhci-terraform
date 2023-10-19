module "efs" {
  source = "terraform-aws-modules/efs/aws"

  # File system
  name           = "efs-${local.name}"
  encrypted      = true

  lifecycle_policy = {
    transition_to_ia = "AFTER_30_DAYS"
  }

  # File system policy
  attach_policy                      = true
  bypass_policy_lockout_safety_check = false

  # Mount targets / security group
  mount_targets = {
    "eu-west-1a" = {
      subnet_id = "subnet-abcde012"
    }
    "eu-west-1b" = {
      subnet_id = "subnet-bcde012a"
    }
    "eu-west-1c" = {
      subnet_id = "subnet-fghi345a"
    }
  }
  security_group_description = "Example EFS security group"
  security_group_vpc_id      = "vpc-1234556abcdef"
  security_group_rules = {
    vpc = {
      # relying on the defaults provdied for EFS/NFS (2049/TCP + ingress)
      description = "NFS ingress from VPC private subnets"
      cidr_blocks = ["10.99.3.0/24", "10.99.4.0/24", "10.99.5.0/24"]
    }
  }

  # Access point(s)
  access_points = {
    posix_example = {
      name = "posix-example"
      posix_user = {
        gid            = 1001
        uid            = 1001
        secondary_gids = [1002]
      }

      tags = {
        Additionl = "yes"
      }
    }
    root_example = {
      root_directory = {
        path = "/example"
        creation_info = {
          owner_gid   = 1001
          owner_uid   = 1001
          permissions = "755"
        }
      }
    }
  }

  # Backup policy
  enable_backup_policy = false

  tags = local.tags
}
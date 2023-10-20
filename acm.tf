variable "tld" {
  type        = string
  description = "The top level domain name (such as lhci.com)"
}

variable "subdomain" {
  type        = string
  description = "The sub-domain value (such as test)"
}

# variable "cert_san" {
#   type        = list(any)
#   description = "List of subject alternative domain names"
# }

data "aws_route53_zone" "selected" {
  name         = "${var.tld}."
  private_zone = false
}

module "acm" {
  source  = "terraform-aws-modules/acm/aws"
  version = "~> 4.0"

  domain_name = "${var.subdomain}.${var.tld}"
  zone_id     = data.aws_route53_zone.selected.id

  validation_method = "DNS"

  #   subject_alternative_names = var.cert_san

  wait_for_validation = true

  tags = local.tags
}

module "records" {
  source  = "terraform-aws-modules/route53/aws//modules/records"
  version = "~> 2.0"

  zone_name = data.aws_route53_zone.selected.name

  records = [
    {
      name    = var.subdomain
      type    = "CNAME"
      ttl = 3600
      records = [
        module.alb.lb_dns_name
      ]
    }
  ]

}
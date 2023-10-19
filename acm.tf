variable "tld" {
  type        = string
  description = "The top level domain name (such as lhci.com)"
}

variable "fqdn" {
  type        = string
  description = "Fully qualified domain name (such as test.lhci.com)"
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

  domain_name = var.fqdn
  zone_id     = data.aws_route53_zone.selected.id

  validation_method = "DNS"

  #   subject_alternative_names = var.cert_san

  wait_for_validation = true

  tags = local.tags
}
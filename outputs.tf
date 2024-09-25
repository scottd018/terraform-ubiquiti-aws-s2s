output "resolver_endpoint_ip_addresses" {
  value = var.create_inbound_resolver ? aws_route53_resolver_endpoint.inbound[0].ip_address : null
}

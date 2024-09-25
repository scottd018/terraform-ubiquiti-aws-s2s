resource "aws_customer_gateway" "usg" {
  device_name = "usg"
  ip_address  = var.usg_internet_address
  type        = "ipsec.1"
  bgp_asn     = 65000

  tags = {
    Name = "${var.aws_vpn_name}-cgw"
  }
}

resource "aws_vpn_gateway" "aws" {
  tags = {
    Name = "${var.aws_vpn_name}-vgw"
  }
}

data "aws_subnets" "selected" {
  filter {
    name   = "subnet-id"
    values = var.aws_subnet_ids
  }
}

# TODO: this makes an assumption that all subnets belong to the same vpc
data "aws_subnet" "selected" {
  id = data.aws_subnets.selected.ids[0]
}

# TODO: this makes an assumption that all subnets belong to the same vpc
data "aws_vpc" "selected" {
  id = data.aws_subnet.selected.vpc_id
}

data "aws_route_table" "selected" {
  count = length(var.aws_subnet_ids)

  subnet_id = data.aws_subnets.selected.ids[count.index]
}

resource "aws_vpn_gateway_attachment" "vpn_attachment" {
  vpc_id         = data.aws_vpc.selected.id
  vpn_gateway_id = aws_vpn_gateway.aws.id
}

resource "random_string" "pre_shared_key" {
  count = 2

  length           = 64
  lower            = true
  upper            = true
  special          = true
  override_special = "_."

  # only skip numeric because we cannot guarantee the requirement that 
  # the random string does not start with a '0' character
  numeric = false
}

resource "aws_vpn_connection" "aws_to_usg" {
  vpn_gateway_id      = aws_vpn_gateway.aws.id
  customer_gateway_id = aws_customer_gateway.usg.id
  type                = "ipsec.1"
  static_routes_only  = true

  # tunnel1
  tunnel1_ike_versions                 = [local.ipsec_ike_version]
  tunnel1_preshared_key                = random_string.pre_shared_key[0].result
  tunnel1_phase1_encryption_algorithms = [upper(local.ipsec_encryption_algorithm)]
  tunnel1_phase1_integrity_algorithms  = [upper(local.ipsec_integrity_algorithm)]
  tunnel1_phase1_lifetime_seconds      = local.ipsec_phase1_lifetime_seconds
  tunnel1_phase1_dh_group_numbers      = [local.ipsec_dh_group_number]
  tunnel1_phase2_encryption_algorithms = [upper(local.ipsec_encryption_algorithm)]
  tunnel1_phase2_integrity_algorithms  = [upper(local.ipsec_integrity_algorithm)]
  tunnel1_phase2_lifetime_seconds      = local.ipsec_phase2_lifetime_seconds
  tunnel1_phase2_dh_group_numbers      = [local.ipsec_dh_group_number]
  tunnel1_startup_action               = "start"

  # tunnel2
  tunnel2_ike_versions                 = [local.ipsec_ike_version]
  tunnel2_preshared_key                = random_string.pre_shared_key[1].result
  tunnel2_phase1_encryption_algorithms = [upper(local.ipsec_encryption_algorithm)]
  tunnel2_phase1_integrity_algorithms  = [upper(local.ipsec_integrity_algorithm)]
  tunnel2_phase1_lifetime_seconds      = local.ipsec_phase1_lifetime_seconds
  tunnel2_phase1_dh_group_numbers      = [local.ipsec_dh_group_number]
  tunnel2_phase2_encryption_algorithms = [upper(local.ipsec_encryption_algorithm)]
  tunnel2_phase2_integrity_algorithms  = [upper(local.ipsec_integrity_algorithm)]
  tunnel2_phase2_lifetime_seconds      = local.ipsec_phase2_lifetime_seconds
  tunnel2_phase2_dh_group_numbers      = [local.ipsec_dh_group_number]
  tunnel2_startup_action               = "add"

  tags = {
    Name = "${var.aws_vpn_name}-vpn"
  }
}

resource "aws_vpn_connection_route" "home" {
  count = length(var.usg_destination_cidrs)

  destination_cidr_block = var.usg_destination_cidrs[count.index]
  vpn_connection_id      = aws_vpn_connection.aws_to_usg.id
}

resource "aws_vpn_gateway_route_propagation" "home" {
  count = length(data.aws_route_table.selected)

  vpn_gateway_id = aws_vpn_gateway.aws.id
  route_table_id = data.aws_route_table.selected[count.index].id
}

#
# inbound resolver
#
resource "aws_security_group" "resolver" {
  count = var.create_inbound_resolver ? 1 : 0

  name        = "route53-resolver"
  description = "Security group for Route 53 Resolver Inbound Endpoint"
  vpc_id      = data.aws_vpc.selected.id

  # Allow inbound DNS queries (TCP/UDP) on port 53 from the USG side of the connection
  ingress {
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = var.usg_destination_cidrs
  }

  ingress {
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = var.usg_destination_cidrs
  }

  tags = {
    Name = "${data.aws_vpc.selected.id}-resolver-inbound-sg"
  }
}

locals {
  needs_ip = var.create_inbound_resolver && length(data.aws_subnets.selected.ids) == 1
}

# TODO: if same subnet is specific we must choose a random ip which may have conflicts because we need 2 unique
# subnets per the TF provider input. see https://github.com/hashicorp/terraform-provider-aws/issues/28233
data "aws_network_interfaces" "used" {
  count = local.needs_ip ? 1 : 0

  filter {
    name   = "subnet-id"
    values = [data.aws_subnets.selected.ids[count.index]]
  }
}

data "aws_network_interface" "used" {
  count = local.needs_ip ? length(data.aws_network_interfaces.used[0].ids) : 0

  id = data.aws_network_interfaces.used[0].ids[count.index]
}

locals {
  sorted_ips_as_integers = local.needs_ip ? sort([
    for interface in data.aws_network_interface.used :
    tonumber(split(".", interface.private_ip)[0]) * 16777216 + # 2^24
    tonumber(split(".", interface.private_ip)[1]) * 65536 +    # 2^16
    tonumber(split(".", interface.private_ip)[2]) * 256 +      # 2^8
    tonumber(split(".", interface.private_ip)[3])              # 2^0
  ]) : []

  # TODO: this makes an assumption that the last available IP in the range is not the last
  # in this list or that this IP is not resreved by AWS
  next_ip_integer = local.needs_ip ? local.sorted_ips_as_integers[length(local.sorted_ips_as_integers) - 1] + 1 : 0

  next_ip = local.needs_ip ? join(".", [
    tostring(floor(local.next_ip_integer / 16777216)),           # 2^24
    tostring(floor((local.next_ip_integer % 16777216) / 65536)), # 2^16
    tostring(floor((local.next_ip_integer % 65536) / 256)),      # 2^8
    tostring(local.next_ip_integer % 256)                        # 2^0
  ]) : ""
}

resource "aws_route53_resolver_endpoint" "inbound" {
  count = var.create_inbound_resolver ? 1 : 0

  direction          = "INBOUND"
  security_group_ids = [aws_security_group.resolver[0].id]

  ip_address {
    subnet_id = data.aws_subnets.selected.ids[0]
  }

  # TODO: if same subnet is specific we must choose a random ip which may have conflicts because we need 2 unique
  # subnets per the TF provider input. see https://github.com/hashicorp/terraform-provider-aws/issues/28233
  ip_address {
    subnet_id = length(data.aws_subnets.selected.ids) == 1 ? data.aws_subnets.selected.ids[0] : data.aws_subnets.selected.ids[1]
    ip        = length(data.aws_subnets.selected.ids) == 1 ? local.next_ip : null
  }

  protocols = ["Do53"]

  tags = {
    Name = "${data.aws_vpc.selected.id}-inbound-resolver"
  }
}

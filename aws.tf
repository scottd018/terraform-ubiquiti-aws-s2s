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

data "aws_vpc" "selected" {
  id = distinct(data.aws_subnets.selected.vpc_ids)[0]
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

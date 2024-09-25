#
# login and current state
#
locals {
  login_data = jsonencode(
    {
      username = var.usg_username,
      password = var.usg_password,
    }
  )
}

data "http" "login" {
  url      = "${var.usg_api_url}/api/auth/login"
  method   = "POST"
  insecure = true

  request_body = local.login_data

  request_headers = {
    "Content-Type" = "application/json"
  }

  lifecycle {
    postcondition {
      condition     = contains([200], self.status_code)
      error_message = "Could not login to Ubiquiti API.  Status code [${self.status_code}] invalid.  Expected 200."
    }

    postcondition {
      condition     = coalesce(lookup(self.response_headers, "Set-Cookie", null), null) != null
      error_message = "Could not login to Ubiquiti API.  Set-Cookie missing from response headers."
    }

    postcondition {
      condition     = coalesce(lookup(self.response_headers, "X-Csrf-Token", null), null) != null
      error_message = "Could not login to Ubiquiti API.  X-Csrf-Token missing from response headers."
    }
  }
}

locals {
  auth_token = regex("TOKEN=([^;]+)", data.http.login.response_headers["Set-Cookie"])[0]
  csrf_token = data.http.login.response_headers["X-Csrf-Token"]
}

data "http" "current_site_config" {
  url      = "${var.usg_api_url}/proxy/network/api/self/sites"
  method   = "GET"
  insecure = true

  request_headers = {
    "Content-Type" = "application/json",
    "Cookie"       = "TOKEN=${local.auth_token}"
  }

  lifecycle {
    postcondition {
      condition     = contains([200], self.status_code)
      error_message = "Could not GET site config.  Status code [${self.status_code}] invalid.  Expected 200."
    }
  }
}

locals {
  site_name = [
    for site in jsondecode(data.http.current_site_config.response_body).data : site.name if site.desc == var.usg_site
  ][0]
  site_id = [
    for site in jsondecode(data.http.current_site_config.response_body).data : site._id if site.desc == var.usg_site
  ][0]
}

data "http" "current_network_config" {
  url      = "${var.usg_api_url}/proxy/network/api/s/${local.site_name}/rest/networkconf"
  method   = "GET"
  insecure = true

  request_headers = {
    "Content-Type" = "application/json",
    "Cookie"       = "TOKEN=${local.auth_token}"
  }

  lifecycle {
    postcondition {
      condition     = contains([200], self.status_code)
      error_message = "Could not GET network config.  Status code [${self.status_code}] invalid.  Expected 200."
    }
  }
}

#
# profiles and groups
#
resource "unifi_firewall_group" "aws_vpn_addresses" {
  site = local.site_name

  name    = "address_aws_vpn_${data.aws_vpc.selected.id}"
  type    = "address-group"
  members = [aws_vpn_connection.aws_to_usg.tunnel1_address, aws_vpn_connection.aws_to_usg.tunnel2_address]
}

resource "unifi_firewall_group" "aws_vpn_ports" {
  site = local.site_name

  name    = "port_aws_vpn_${data.aws_vpc.selected.id}"
  type    = "port-group"
  members = ["500", "4500"]
}

resource "unifi_firewall_group" "aws_esg_ports" {
  site = local.site_name

  name    = "port_aws_vpn_esg_${data.aws_vpc.selected.id}"
  type    = "port-group"
  members = ["50"]
}

resource "unifi_firewall_group" "local_vpn_addresses" {
  site = local.site_name

  name    = "address_local_vpn_${data.aws_vpc.selected.id}"
  type    = "address-group"
  members = var.usg_destination_cidrs
}

#
# firewall configuration
#

# AWS docs for Site-to-Site VPN: https://docs.aws.amazon.com/vpn/latest/s2svpn/FirewallRules.html
# Ubiquti docs for API: https://ubntwiki.com/products/software/unifi-controller/api
# CLI video: https://www.youtube.com/watch?v=CYEkG-o9I5M
resource "unifi_firewall_rule" "aws_vpn_cgw_udp_500_in" {
  site = local.site_name

  name       = "allow_aws_vpn_udp_in"
  action     = "accept"
  ruleset    = "WAN_LOCAL"
  enabled    = true
  rule_index = 2020 #TODO
  protocol   = "udp"

  src_firewall_group_ids = [
    unifi_firewall_group.aws_vpn_addresses.id,
    unifi_firewall_group.aws_vpn_ports.id
  ]

  dst_firewall_group_ids = [
    unifi_firewall_group.local_vpn_addresses.id,
    unifi_firewall_group.aws_vpn_ports.id
  ]
}

resource "unifi_firewall_rule" "aws_vpn_cgw_esg_50_in" {
  site = local.site_name

  name       = "allow_aws_vpn_esg_in"
  action     = "accept"
  ruleset    = "WAN_LOCAL"
  enabled    = true
  rule_index = 2021 #TODO
  protocol   = "esg"

  src_firewall_group_ids = [
    unifi_firewall_group.aws_vpn_addresses.id,
    unifi_firewall_group.aws_esg_ports.id
  ]

  dst_firewall_group_ids = [
    unifi_firewall_group.local_vpn_addresses.id,
    unifi_firewall_group.aws_esg_ports.id
  ]
}

# see https://community.ui.com/questions/Unifi-OS-API-VPN-endpoints/ce784eed-ebcd-4daf-a10f-d31f362ecbc6?page=1 for payload
# example
# TLDR = https://<controller_ip>/proxy/network/api/s/<site_id>/rest/networkconf API call gets the full payload
locals {
  vpn_payload = {
    # static payload values
    "enabled" : true,
    "ipsec_tunnel_ip_enabled" : true,
    "ipsec_pfs" : true,
    "ipsec_dynamic_routing" : true,
    "ipsec_separate_ikev2_networks" : false,
    "purpose" : "site-vpn",
    "vpn_type" : "ipsec-vpn",
    "ifname" : "vti64",
    "ipsec_interface" : "wan",
    "ipsec_local_identifier_enabled" : false,
    "ipsec_local_identifier" : "",
    "ipsec_remote_identifier_enabled" : false,
    "ipsec_remote_identifier" : "",
    "interface_mtu_enabled" : true,
    "interface_mtu" : 1436,
    "route_distance" : 30,

    # dynamic payload values
    "name" : "aws_${var.aws_region}_${data.aws_vpc.selected.id}",
    "site_id" : "${local.site_id}",
    "ipsec_dh_group" : local.ipsec_dh_group_number,
    "ipsec_esp_dh_group" : local.ipsec_dh_group_number,
    "ipsec_ike_encryption" : lower(local.ipsec_encryption_algorithm),
    "ipsec_esp_lifetime" : local.ipsec_phase2_lifetime_seconds,
    "ipsec_key_exchange" : local.ipsec_ike_version,
    "ipsec_tunnel_ip" : "${aws_vpn_connection.aws_to_usg.tunnel1_cgw_inside_address}/30",
    "x_ipsec_pre_shared_key" : random_string.pre_shared_key[0].result,
    "ipsec_ike_dh_group" : local.ipsec_dh_group_number,
    "ipsec_peer_ip" : aws_vpn_connection.aws_to_usg.tunnel1_address,
    "ipsec_ike_hash" : lower(local.ipsec_integrity_algorithm),
    "ipsec_esp_hash" : lower(local.ipsec_integrity_algorithm),
    "ipsec_ike_lifetime" : local.ipsec_phase1_lifetime_seconds,
    "ipsec_esp_encryption" : lower(local.ipsec_encryption_algorithm),
    "ipsec_local_ip" : "${var.usg_internet_address}"
    "remote_vpn_subnets" : [
      data.aws_vpc.selected.cidr_block
    ],
  }
}

locals {
  vpn_config = [
    for config in jsondecode(data.http.current_network_config.response_body).data : local.vpn_payload if local.vpn_payload.name == config.name
  ]
  needs_create = length(local.vpn_config) == 0

  vpn_config_id = local.needs_create ? [
    jsondecode(data.http.add_vpn_config[0].response_body).data[0]._id
    ] : [
    for config in jsondecode(data.http.current_network_config.response_body).data : config._id if local.vpn_payload.name == config.name
  ]
}

data "http" "add_vpn_config" {
  count = local.needs_create ? 1 : 0

  url      = "${var.usg_api_url}/proxy/network/api/s/${local.site_name}/rest/networkconf"
  method   = "POST"
  insecure = true

  request_body = jsonencode(local.vpn_payload)

  request_headers = {
    "Content-Type" = "application/json",
    "Cookie"       = "TOKEN=${local.auth_token}",
    "X-Csrf-Token" = local.csrf_token
  }

  lifecycle {
    postcondition {
      condition     = contains([200], self.status_code)
      error_message = "Could not POST VPN config.  Status code [${self.status_code}] invalid.  Expected 200."
    }
  }
}

resource "terraform_data" "destroy_vpn_config" {
  input = {
    api_url       = var.usg_api_url,
    site_name     = local.site_name,
    vpn_config_id = local.vpn_config_id[0],
    auth_token    = local.auth_token,
    csrf_token    = local.csrf_token
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<EOF
    curl ${self.input.api_url}/proxy/network/api/s/${self.input.site_name}/rest/networkconf/${self.input.vpn_config_id} \
      --silent \
      --insecure \
      --request DELETE \
      --header 'Content-Type: application/json' \
      --header 'Cookie: TOKEN=${self.input.auth_token}' \
      --header 'X-Csrf-Token: ${self.input.csrf_token}'
    EOF
  }
}

resource "unifi_static_route" "interface" {
  site = local.site_name

  name      = "route_aws_vpn"
  type      = "interface-route"
  network   = data.aws_vpc.selected.cidr_block
  distance  = 1
  interface = local.vpn_config_id[0]

  depends_on = [data.http.add_vpn_config, resource.terraform_data.destroy_vpn_config]
}

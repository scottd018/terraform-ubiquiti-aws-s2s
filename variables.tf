#
# aws variables
#
variable "aws_region" {
  description = "The AWS region to provision AWS resources into."
  type        = string
  default     = "us-east-1"
}

variable "aws_vpn_name" {
  type        = string
  default     = "dscott"
  description = "Used for naming AWS VPN resources."
}

variable "aws_vpc_id" {
  type        = string
  description = "VPC used for creating the VPN resources and established connections."
}

#
# ubiquiti usg variables
#
variable "usg_destination_cidrs" {
  type        = list(string)
  description = "CIDRs which should use the VPN gateway for routing traffic to.  These should be on the non-AWS site of the VPN connection."
}

variable "usg_username" {
  type        = string
  default     = "admin"
  description = "Username used for connecting to the USG for management."
  sensitive   = true
}

variable "usg_password" {
  type        = string
  description = "Password used for the 'usg_username' used for connecting to the USG for management."
  sensitive   = true
}

variable "usg_api_url" {
  type        = string
  description = "URL used for making API requests against the USG for management."
  sensitive   = true
}

variable "usg_site" {
  type        = string
  default     = "Default"
  description = "Site description to use for management of USG."
}

variable "usg_internet_address" {
  type        = string
  description = "IP address of the public internet address of the USG.  Used for allowing ports to destination."
}

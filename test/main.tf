
variable "aws_region" {}
variable "aws_vpc_id" {}

variable "usg_destination_cidrs" {}
variable "usg_username" {}
variable "usg_password" {}
variable "usg_api_url" {}
variable "usg_site" {}
variable "usg_internet_address" {}

module "test" {
  source = "../"

  # aws
  aws_region = var.aws_region
  aws_vpc_id = var.aws_vpc_id

  # ubiquiti usg
  usg_destination_cidrs = var.usg_destination_cidrs
  usg_username          = var.usg_username
  usg_password          = var.usg_password
  usg_api_url           = var.usg_api_url
  usg_site              = var.usg_site
  usg_internet_address  = var.usg_internet_address
}

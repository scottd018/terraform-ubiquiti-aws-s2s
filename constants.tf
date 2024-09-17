locals {
  ipsec_ike_version             = "ikev2"
  ipsec_encryption_algorithm    = "aes256"
  ipsec_integrity_algorithm     = "sha1"
  ipsec_dh_group_number         = 14
  ipsec_phase1_lifetime_seconds = 3600
  ipsec_phase2_lifetime_seconds = 3600
}

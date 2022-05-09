module "db_verify" {
  source           = "github.com/kperson/terraform-modules//auto-scaled-dynamo"
  table_name       = "pineappleVerify"
  hash_key         = "verifyKey"
  stream_view_type = "NEW_AND_OLD_IMAGES"
  billing_mode     = "PROVISIONED"
  attributes = [
    {
      name = "verifyKey"
      type = "S"
    }
  ]

  ttl_attribute = {
    name = "ttl"
  }
}

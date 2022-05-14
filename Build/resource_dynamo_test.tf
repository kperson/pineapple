module "db_test" {
  source           = "github.com/kperson/terraform-modules//auto-scaled-dynamo"
  table_name       = "pineapplTest"
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

module "db_test_policy" {
  source     = "github.com/kperson/terraform-modules//dynamo-crud-policy"
  table_arn  = module.db_test.arn
  stream_arn = module.db_test.stream_arn
}

module "db_test_policy_role_attachement" {
  source     = "github.com/kperson/terraform-modules//aws_role_attachment"
  role       = aws_iam_role.lambda.name
  policy_arn = module.db_test_policy.arn
}

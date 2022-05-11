module "ecr_push" {
  source        = "../terraform-support/ecr-push"
  image_uri     = "pineapple"
  ecr_repo_name = "pineappletest"
}

module "sqs_test" {
  source        = "../terraform-support/sqs-lambda"
  depends_on    = [module.ecr_push]
  sqs_arn       = aws_sqs_queue.test_queue.arn
  function_name = "pineapple-sqs"
  role          = module.lambda_role_arn.out
  ecr_repo_name = module.ecr_push.ecr_repo_name
  ecr_repo_tag  = module.ecr_push.ecr_repo_tag
  memory_size   = 256
  timeout       = 30

  env = {
    MY_HANDLER   = "test.sqs"
    VERIFY_TABLE = module.db_verify.id
  }
}

module "sns_test" {
  source        = "../terraform-support/sns-lambda"
  depends_on    = [module.ecr_push]
  topic_arn     = aws_sns_topic.test_topic.arn
  function_name = "pineapple-sns"
  role          = module.lambda_role_arn.out
  ecr_repo_name = module.ecr_push.ecr_repo_name
  ecr_repo_tag  = module.ecr_push.ecr_repo_tag
  memory_size   = 256
  timeout       = 30

  env = {
    MY_HANDLER   = "test.sns"
    VERIFY_TABLE = module.db_verify.id
  }
}
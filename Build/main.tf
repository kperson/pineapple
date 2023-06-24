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
  memory_size   = 512
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
  memory_size   = 512
  timeout       = 30

  env = {
    MY_HANDLER   = "test.sns"
    VERIFY_TABLE = module.db_verify.id
  }
}

module "s3_test" {
  source        = "../terraform-support/s3-lambda"
  depends_on    = [module.ecr_push]
  bucket_name   = aws_s3_bucket.test_bucket.id
  events        = ["s3:ObjectCreated:*", "s3:ObjectRemoved:*"]
  function_name = "pineapple-s3"
  role          = module.lambda_role_arn.out
  ecr_repo_name = module.ecr_push.ecr_repo_name
  ecr_repo_tag  = module.ecr_push.ecr_repo_tag
  memory_size   = 512
  timeout       = 30

  env = {
    MY_HANDLER   = "test.s3"
    VERIFY_TABLE = module.db_verify.id
  }
}

module "dynamo_test" {
  source        = "../terraform-support/dynamo-stream-lambda"
  depends_on    = [module.ecr_push]
  stream_arn    = module.db_test.stream_arn
  function_name = "pineapple-dynamo-stream"
  role          = module.lambda_role_arn.out
  ecr_repo_name = module.ecr_push.ecr_repo_name
  ecr_repo_tag  = module.ecr_push.ecr_repo_tag
  memory_size   = 512
  timeout       = 30

  env = {
    MY_HANDLER   = "test.dynamo"
    VERIFY_TABLE = module.db_verify.id
  }
}

module "http_test" {
  source           = "../terraform-support/api-gateway-lambda"
  depends_on       = [module.ecr_push, aws_api_gateway_rest_api.pineapple]
  api_gateway_name = "pineapple-test"
  stage_name       = "default"
  function_name    = "pineapple-http"
  role             = module.lambda_role_arn.out
  ecr_repo_name    = module.ecr_push.ecr_repo_name
  ecr_repo_tag     = module.ecr_push.ecr_repo_tag
  memory_size      = 512
  timeout          = 30

  env = {
    MY_HANDLER   = "test.http"
    VERIFY_TABLE = module.db_verify.id
  }
}

module "cron_test" {
   source           = "../terraform-support/cron-lambda"
   depends_on       = [module.ecr_push]
   schedule_expression = "cron(* * * * ? *)" // every minute
   function_name    = "pineapple-cron"
   role             = module.lambda_role_arn.out
   ecr_repo_name    = module.ecr_push.ecr_repo_name
   ecr_repo_tag     = module.ecr_push.ecr_repo_tag
   memory_size      = 256
   timeout          = 30

   env = {
     MY_HANDLER   = "test.cron"
     VERIFY_TABLE = module.db_verify.id
   }
 }

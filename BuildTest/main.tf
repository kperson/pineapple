module "ecr_push" {
  source        = "../terraform-support/ecr-push"
  image_uri     = "pineapple"
  ecr_repo_name = "pineappletest"
}

module "sqs_test" {
  source             = "../terraform-support/sqs-lambda"
  sqs_arn            = aws_sqs_queue.test_queue.arn
  function_name      = "pineapple-sqs"
  role               = module.lambda_role_arn.out
  ecr_repository_url = module.ecr_push.ecr_repository_url
  ecr_repo_name      = module.ecr_push.ecr_repo_name
  ecr_repo_tag       = module.ecr_push.ecr_repo_tag
  timeout            = "30"

  env = {
    MY_HANDLER = "test.sqs"
  }
}

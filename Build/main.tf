module "dynamo_stream" {
  source           = "github.com/kperson/terraform-modules//auto-scaled-dynamo"
  table_name       = "pineappleDynamoStream"
  hash_key         = "id"
  stream_view_type = "NEW_AND_OLD_IMAGES"
  billing_mode     = "PROVISIONED"
  attributes = [
    {
      name = "id"
      type = "S"
    }
  ]

  ttl_attribute = {
    name = "ttl"
  }
}

module "ecr_push" {
  source        = "../terraform-support/ecr-push"
  image_uri     = "pineapple"
  ecr_repo_name = "pineappletest"
}

module "sqs_test" {
  source           = "../terraform-support/sqs-lambda"
  depends_on       = [module.ecr_push]
  sqs_arn          = aws_sqs_queue.test_queue.arn
  function_name    = "pineapple-sqs"
  role             = module.lambda_role_arn.out
  ecr_repo_name    = module.ecr_push.ecr_repo_name
  ecr_repo_tag     = module.ecr_push.ecr_repo_tag
  source_code_hash = module.ecr_push.build_timestamp
  memory_size      = 512
  timeout          = 30
  handler          = "test.sqs"

  env = {
    TEST_RUN_KEY = var.test_run_key
    VERIFY_TABLE = module.db_verify.id
    LOG_LEVEL    = var.log_level
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
  handler       = "test.sns"

  env = {
    TEST_RUN_KEY = var.test_run_key
    VERIFY_TABLE = module.db_verify.id
    LOG_LEVEL    = var.log_level
  }
}

module "s3_test_events" {
  source           = "../terraform-support/s3-lambda"
  depends_on       = [module.ecr_push]
  bucket_name      = aws_s3_bucket.test_bucket.id
  events           = ["s3:ObjectCreated:*", "s3:ObjectRemoved:*"]
  function_name    = "pineapple-s3-events"
  role             = module.lambda_role_arn.out
  ecr_repo_name    = module.ecr_push.ecr_repo_name
  ecr_repo_tag     = module.ecr_push.ecr_repo_tag
  source_code_hash = module.ecr_push.build_timestamp
  memory_size      = 512
  timeout          = 30
  handler          = "test.s3-events"

  env = {
    TEST_RUN_KEY = var.test_run_key
    VERIFY_TABLE = module.db_verify.id
    LOG_LEVEL    = var.log_level
  }
}

module "dynamo_test" {
  source        = "../terraform-support/dynamo-stream-lambda"
  depends_on    = [module.ecr_push]
  stream_arn    = module.dynamo_stream.stream_arn
  function_name = "pineapple-dynamo-stream"
  role          = module.lambda_role_arn.out
  ecr_repo_name = module.ecr_push.ecr_repo_name
  ecr_repo_tag  = module.ecr_push.ecr_repo_tag
  memory_size   = 512
  timeout       = 30
  handler       = "test.dynamo"

  env = {
    TEST_RUN_KEY = var.test_run_key
    VERIFY_TABLE = module.db_verify.id
    LOG_LEVEL    = var.log_level
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
  handler          = "test.http"

  env = {
    TEST_RUN_KEY = var.test_run_key
    VERIFY_TABLE = module.db_verify.id
    LOG_LEVEL    = var.log_level
  }
}

module "http_v2_test" {
  source        = "../terraform-support/http-api-lambda"
  depends_on    = [module.ecr_push]
  api_name      = "pineapple-test-v2"
  function_name = "pineapple-httpv2"
  role          = module.lambda_role_arn.out
  ecr_repo_name = module.ecr_push.ecr_repo_name
  ecr_repo_tag  = module.ecr_push.ecr_repo_tag
  memory_size   = 512
  timeout       = 30
  handler       = "test.httpv2"

  env = {
    TEST_RUN_KEY = var.test_run_key
    VERIFY_TABLE = module.db_verify.id
    LOG_LEVEL    = var.log_level
  }
}

# WebSocket Relay - DynamoDB table for connection tracking
resource "aws_dynamodb_table" "relay" {
  name         = "pineappleRelay"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "connectionId"
  range_key    = "sk"

  attribute {
    name = "connectionId"
    type = "S"
  }

  attribute {
    name = "sk"
    type = "S"
  }

  attribute {
    name = "sessionId"
    type = "S"
  }

  global_secondary_index {
    name            = "sessionId-index"
    hash_key        = "sessionId"
    projection_type = "ALL"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }
}

# WebSocket Relay - WS Lambda (handles $connect/$disconnect/$default)
module "ws_relay_test" {
  source           = "../terraform-support/websocket-api-lambda"
  depends_on       = [module.ecr_push]
  api_name         = "pineapple-ws-relay"
  function_name    = "pineapple-ws-relay"
  role             = module.lambda_role_arn.out
  ecr_repo_name    = module.ecr_push.ecr_repo_name
  ecr_repo_tag     = module.ecr_push.ecr_repo_tag
  memory_size      = 512
  timeout          = 30
  handler          = "test.ws-relay"

  env = {
    TEST_RUN_KEY       = var.test_run_key
    VERIFY_TABLE       = module.db_verify.id
    RELAY_TABLE_NAME   = aws_dynamodb_table.relay.name
    LOG_LEVEL          = var.log_level
  }
}

# WebSocket Relay - HTTP Lambda (handles MCP client POST requests)
module "http_relay_test" {
  source        = "../terraform-support/http-api-lambda"
  depends_on    = [module.ecr_push]
  api_name      = "pineapple-http-relay"
  function_name = "pineapple-http-relay"
  role          = module.lambda_role_arn.out
  ecr_repo_name = module.ecr_push.ecr_repo_name
  ecr_repo_tag  = module.ecr_push.ecr_repo_tag
  memory_size   = 512
  timeout       = 30
  handler       = "test.http-relay"

  env = {
    TEST_RUN_KEY           = var.test_run_key
    VERIFY_TABLE           = module.db_verify.id
    RELAY_TABLE_NAME       = aws_dynamodb_table.relay.name
    WS_MANAGEMENT_ENDPOINT = module.ws_relay_test.ws_management_endpoint
    LOG_LEVEL              = var.log_level
  }
}

module "cron_test" {
  source              = "../terraform-support/cron-lambda"
  depends_on          = [module.ecr_push]
  schedule_expression = "cron(* * * * ? *)" // every minute
  function_name       = "pineapple-cron"
  role                = module.lambda_role_arn.out
  ecr_repo_name       = module.ecr_push.ecr_repo_name
  ecr_repo_tag        = module.ecr_push.ecr_repo_tag
  memory_size         = 256
  timeout             = 30
  handler             = "test.cron"

  env = {
    TEST_RUN_KEY = "integration-test"
    VERIFY_TABLE = module.db_verify.id
    LOG_LEVEL    = "debug"
  }
}

resource "aws_api_gateway_rest_api" "proxy" {
  name               = "lambda-local-proxy"
  binary_media_types = ["*/*"]

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

module "lambda_proxy_events" {
  source       = "github.com/kperson/terraform-modules//auto-scaled-dynamo"
  table_name   = format("%s_lambda_proxy_events", terraform.workspace)
  hash_key     = "namespaceKey"
  range_key    = "payloadCreatedAt"
  billing_mode = "PAY_PER_REQUEST"

  attributes = [
    {
      name = "namespaceKey"
      type = "S"
    },
    {
      name = "payloadCreatedAt"
      type = "N"
    },
    {
      name = "requestId"
      type = "S"
    }
  ]

  global_secondary_indices = [
    {
      name      = "requestIdIndex"
      hash_key  = "requestId"
      range_key = null
    }
  ]
}

module "proxy" {
  source        = "./http-lambda"
  image_uri     = "pineapple"
  memory_size   = "512"
  timeout       = "30"
  ecr_repo_name = "pineapple-proxy"

  env = {
    MY_HANDLER = "com.kperson.http"
  }

  role                 = module.lambda_role_arn.out
  function_name        = "lambda_local_proxy"
  stage_name           = "default"
  authorization        = "NONE"
  api_id               = aws_api_gateway_rest_api.proxy.id
  api_root_resource_id = aws_api_gateway_rest_api.proxy.root_resource_id
  command              = ["/LambaProxyRuntimeAPI"]
}

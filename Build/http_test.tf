resource "aws_api_gateway_rest_api" "http-test" {
  name = "http-test"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

module "http_test" {
  source      = "./http-lambda"
  image_uri   = "pineapple_runtime-api-test:latest"
  memory_size = "512"
  timeout     = "30"
  ecr_repo_name = "httptest"

  env = {
    HELLO = "world"
  }

  role                 = module.lambda_role_arn.out
  function_name        = "http_test"
  stage_name           = "default"
  authorization        = "NONE"
  api_id               = aws_api_gateway_rest_api.http-test.id
  api_root_resource_id = aws_api_gateway_rest_api.http-test.root_resource_id
}

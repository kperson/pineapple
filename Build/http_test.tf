resource "aws_api_gateway_rest_api" "http-test" {
  name               = "http-test"
  binary_media_types = ["*/*"]

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

module "http_test" {
  source        = "./http-lambda"
  image_uri     = "pineapple"
  memory_size   = "512"
  timeout       = "30"
  ecr_repo_name = "httptest"

  env = {
    MY_HANDLER           = "com.kperson.http"
    RUN_AS_LAMBDA        = "1"
    SHOULD_PROXY_REQUEST = "1"
    PROXY_NAMESPACE_KEY  = "test"
    PROXY_BASE_URL = "https://l3d3h98131.execute-api.us-east-1.amazonaws.com/default"
  }

  role                 = module.lambda_role_arn.out
  function_name        = "http_test"
  stage_name           = "default"
  authorization        = "NONE"
  api_id               = aws_api_gateway_rest_api.http-test.id
  api_root_resource_id = aws_api_gateway_rest_api.http-test.root_resource_id
  command              = ["/LambdaVaporDemo"]
}

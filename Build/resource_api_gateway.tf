resource "aws_api_gateway_rest_api" "pineapple" {
  name = "pineapple-test"

  binary_media_types = ["*/*"]

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}


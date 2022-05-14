resource "aws_api_gateway_rest_api" "pineapple" {
  name = "pineapple-test"

  binary_media_types       = ["*/*"]
  minimum_compression_size = 0

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

output "endpoint" {
  value = module.http_test.endpoint
}
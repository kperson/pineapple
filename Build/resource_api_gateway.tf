resource "aws_api_gateway_rest_api" "pineapple" {
  name = "pineapple-test"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}
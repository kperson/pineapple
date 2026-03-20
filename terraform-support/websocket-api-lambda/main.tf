# WebSocket API Gateway + Lambda
#
# Creates a WebSocket API Gateway that routes $connect, $disconnect, and $default
# events to a single Lambda function.

# Variables
variable "api_name" {
  type = string
}

variable "stage_name" {
  type    = string
  default = "production"
}

variable "function_name" {
  type = string
}

variable "ecr_repo_name" {
  type = string
}

variable "ecr_repo_tag" {
  type    = string
  default = "latest"
}

variable "role" {
  type = string
}

variable "handler" {
  type = string
}

variable "env" {
  type    = map(string)
  default = {}
}

variable "memory_size" {
  type    = number
  default = null
}

variable "timeout" {
  type    = number
  default = null
}

variable "source_code_hash" {
  type    = string
  default = ""
}

variable "log_retention_in_days" {
  type    = number
  default = 30
}

# Docker Image
data "aws_ecr_image" "image" {
  repository_name = var.ecr_repo_name
  image_tag       = var.ecr_repo_tag
}

data "aws_ecr_repository" "image" {
  name = var.ecr_repo_name
}

# Logs
resource "aws_cloudwatch_log_group" "lambda" {
  name              = format("/aws/lambda/%s", var.function_name)
  retention_in_days = var.log_retention_in_days
}

# Lambda
resource "aws_lambda_function" "lambda" {
  depends_on                     = [aws_cloudwatch_log_group.lambda]
  function_name                  = var.function_name
  role                           = var.role
  publish                        = true
  package_type                   = "Image"
  architectures                  = ["arm64"]
  memory_size                    = var.memory_size
  timeout                        = var.timeout
  source_code_hash               = trimprefix(data.aws_ecr_image.image.id, "sha256:")

  environment {
    variables = var.env
  }

  image_uri = format("%s:%s", data.aws_ecr_repository.image.repository_url, var.ecr_repo_tag)

  image_config {
    command = [var.handler]
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# WebSocket API Gateway
resource "aws_apigatewayv2_api" "ws" {
  name                       = var.api_name
  protocol_type              = "WEBSOCKET"
  route_selection_expression = "$request.body.action"
}

# Integration (Lambda proxy)
resource "aws_apigatewayv2_integration" "ws" {
  api_id                    = aws_apigatewayv2_api.ws.id
  integration_type          = "AWS_PROXY"
  integration_uri           = aws_lambda_function.lambda.invoke_arn
  content_handling_strategy  = "CONVERT_TO_TEXT"
}

# Routes: $connect, $disconnect, $default
resource "aws_apigatewayv2_route" "connect" {
  api_id    = aws_apigatewayv2_api.ws.id
  route_key = "$connect"
  target    = format("integrations/%s", aws_apigatewayv2_integration.ws.id)
}

resource "aws_apigatewayv2_route" "disconnect" {
  api_id    = aws_apigatewayv2_api.ws.id
  route_key = "$disconnect"
  target    = format("integrations/%s", aws_apigatewayv2_integration.ws.id)
}

resource "aws_apigatewayv2_route" "default" {
  api_id    = aws_apigatewayv2_api.ws.id
  route_key = "$default"
  target    = format("integrations/%s", aws_apigatewayv2_integration.ws.id)
}

# Stage (auto-deploy)
resource "aws_apigatewayv2_stage" "ws" {
  api_id      = aws_apigatewayv2_api.ws.id
  name        = var.stage_name
  auto_deploy = true
}

# Lambda permission for WebSocket API
resource "aws_lambda_permission" "ws" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda.arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = format("%s/*/*", aws_apigatewayv2_api.ws.execution_arn)
}

# Outputs
output "ws_endpoint" {
  description = "WebSocket endpoint URL (wss://...)"
  value       = format("wss://%s.execute-api.%s.amazonaws.com/%s", aws_apigatewayv2_api.ws.id, data.aws_region.current.name, var.stage_name)
}

output "ws_management_endpoint" {
  description = "API Gateway Management API endpoint (for PostToConnection)"
  value       = format("https://%s.execute-api.%s.amazonaws.com/%s", aws_apigatewayv2_api.ws.id, data.aws_region.current.name, var.stage_name)
}

output "ws_api_id" {
  value = aws_apigatewayv2_api.ws.id
}

output "ws_execution_arn" {
  value = aws_apigatewayv2_api.ws.execution_arn
}

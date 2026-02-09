# HTTP API (API Gateway V2)
variable "api_name" {
  type = string
}

variable "stage_name" {
  type    = string
  default = "$default"
}

# Common
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

variable "command" {
  type    = list(string)
  default = null
}

variable "entry_point" {
  type    = list(string)
  default = null
}

variable "handler" {
  type = string
}

variable "env" {
  type    = map(string)
  default = {}
}

variable "subnet_ids" {
  type    = list(string)
  default = []
}

variable "security_group_ids" {
  type    = list(string)
  default = []
}

variable "reserved_concurrent_executions" {
  type    = number
  default = -1
}

variable "memory_size" {
  type    = number
  default = null
}

variable "timeout" {
  type    = number
  default = null
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
  reserved_concurrent_executions = var.reserved_concurrent_executions

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = var.security_group_ids
  }

  environment {
    variables = var.env
  }

  image_uri = format("%s:%s", data.aws_ecr_repository.image.repository_url, var.ecr_repo_tag)

  image_config {
    command     = var.command != null ? var.command : [var.handler]
    entry_point = var.entry_point
  }
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# HTTP API (API Gateway V2)
resource "aws_apigatewayv2_api" "api" {
  name          = var.api_name
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "api" {
  api_id                 = aws_apigatewayv2_api.api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.lambda.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "api" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "$default"
  target    = format("integrations/%s", aws_apigatewayv2_integration.api.id)
}

resource "aws_apigatewayv2_stage" "api" {
  api_id      = aws_apigatewayv2_api.api.id
  name        = var.stage_name
  auto_deploy = true
}

resource "aws_lambda_permission" "api" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda.arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = format("%s/*/*", aws_apigatewayv2_api.api.execution_arn)
}

output "endpoint" {
  depends_on = [aws_apigatewayv2_stage.api]
  value      = aws_apigatewayv2_stage.api.invoke_url
}

output "stage" {
  depends_on = [aws_apigatewayv2_stage.api]
  value      = var.stage_name
}

output "api_id" {
  value = aws_apigatewayv2_api.api.id
}

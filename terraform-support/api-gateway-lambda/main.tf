//API Gateway
variable "api_gateway_name" {
  type = string
}

variable "authorization" {
  type    = string
  default = "NONE"
}

variable "authorizer_id" {
  type    = string
  default = null
}

variable "api_key_required" {
  type    = string
  default = null
}

variable "authorization_scopes" {
  type    = list(string)
  default = null
}

variable "stage_name" {
  type    = string
  default = null
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
    command     = var.command
    entry_point = var.entry_point
  }
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_api_gateway_rest_api" "api" {
  name = var.api_gateway_name
}

resource "aws_api_gateway_resource" "api" {
  rest_api_id = data.aws_api_gateway_rest_api.api.id
  parent_id   = data.aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "api" {
  rest_api_id          = data.aws_api_gateway_rest_api.api.id
  resource_id          = aws_api_gateway_resource.api.id
  http_method          = "ANY"
  authorization        = var.authorization
  authorizer_id        = var.authorizer_id
  api_key_required     = var.api_key_required
  authorization_scopes = var.authorization_scopes
}

resource "aws_api_gateway_integration" "api" {
  rest_api_id             = data.aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.api.id
  http_method             = aws_api_gateway_method.api.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = format("arn:aws:apigateway:%s:lambda:path/2015-03-31/functions/%s/invocations", data.aws_region.current.name, aws_lambda_function.lambda.arn)
}

resource "aws_lambda_permission" "api" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda.arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = format("arn:aws:execute-api:%s:%s:%s/*/*/*", data.aws_region.current.name, data.aws_caller_identity.current.account_id, data.aws_api_gateway_rest_api.api.id)
}


resource "aws_api_gateway_deployment" "api" {
  depends_on  = [aws_api_gateway_integration.api]
  rest_api_id = data.aws_api_gateway_rest_api.api.id
  stage_name  = var.stage_name
}

output "stage" {
  depends_on = [aws_api_gateway_deployment.api]
  value      = var.stage_name
}

output "endpoint" {
  depends_on = [aws_api_gateway_deployment.api]
  value = format(
    "https://%s.execute-api.%s.amazonaws.com/%s",
    data.aws_api_gateway_rest_api.api.id,
    data.aws_region.current.name,
    var.stage_name
  )
}
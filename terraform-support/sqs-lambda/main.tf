# SQS
variable "sqs_arn" {
  type = string
}

variable "batch_size" {
  type    = number
  default = 10
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

resource "aws_lambda_event_source_mapping" "lambda" {
  batch_size       = var.batch_size
  event_source_arn = var.sqs_arn
  enabled          = true
  function_name    = aws_lambda_function.lambda.arn
}

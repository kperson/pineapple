# S3
variable "bucket_name" {
  type = string
}

# https://docs.aws.amazon.com/AmazonS3/latest/userguide/notification-how-to-event-types-and-destinations.html#supported-notification-event-types
# See link above for list of events
variable "events" {
  type = list(string)
}

variable "filter_prefix" {
  type = string
  default = null
}

variable "filter_suffix" {
  type = string
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

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_notification
data "aws_s3_bucket" "lambda" {
  bucket = var.bucket_name
}

resource "aws_lambda_permission" "lambda" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = data.aws_s3_bucket.lambda.arn
}

resource "aws_s3_bucket_notification" "lambda" {
  bucket =  data.aws_s3_bucket.lambda.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.lambda.arn
    events              = var.events
    filter_prefix       = var.filter_prefix
    filter_suffix       = var.filter_suffix
  }

  depends_on = [aws_lambda_permission.lambda]
}
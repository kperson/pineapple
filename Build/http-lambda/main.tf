variable "env" {
  type    = map(string)
  default = {}
}

variable "command" {
  type    = list(string)
  default = null
}

variable "role" {
  type = string
}

variable "subnet_ids" {
  type    = list(string)
  default = []
}

variable "security_group_ids" {
  type    = list(string)
  default = []
}

# Common
variable "function_name" {
  type = string
}

variable "handler" {
  type    = string
  default = null
}

# Common Custom
variable "memory_size" {
  type    = string
  default = "256"
}

variable "timeout" {
  type    = string
  default = "30"
}

# HTTP

variable "api_id" {
  type = string
}

variable "api_root_resource_id" {
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

variable "image_uri" {
  type = string
}

variable "entry_point" {
  type    = list(string)
  default = null
}

variable "ecr_repo_name" {
  type = string
}

resource "aws_ecr_repository" "ecr_repo" {
  name                 = var.ecr_repo_name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "ecr_policy" {
  repository = aws_ecr_repository.ecr_repo.name

  policy = <<EOF
{
    "rules": [
        {
            "rulePriority": 1,
            "description": "Expire images older than 30 days",
            "selection": {
                "tagStatus": "untagged",
                "countType": "sinceImagePushed",
                "countUnit": "days",
                "countNumber": 30
            },
            "action": {
                "type": "expire"
            }
        }
    ]
}
EOF
}

data "aws_ecr_authorization_token" "ecr_token" {
  registry_id = aws_ecr_repository.ecr_repo.registry_id
}

resource "null_resource" "docker_login" {
  triggers = {
    time = timestamp()
  }

  provisioner "local-exec" {

    command = format("docker login --username %s --password %s %s", data.aws_ecr_authorization_token.ecr_token.user_name, data.aws_ecr_authorization_token.ecr_token.password, data.aws_ecr_authorization_token.ecr_token.proxy_endpoint)
    environment = {
    }
  }
}

resource "null_resource" "build_and_push" {
  triggers = {
    time = timestamp()
  }

  depends_on = [null_resource.docker_login]

  provisioner "local-exec" {

    command = format(
      "docker tag %s %s:latest && docker push %s:latest && docker rmi %s:latest",
      var.image_uri,
      aws_ecr_repository.ecr_repo.repository_url,
      aws_ecr_repository.ecr_repo.repository_url,
      aws_ecr_repository.ecr_repo.repository_url
    )
    environment = {
    }
  }
}

data "aws_ecr_image" "image" {
  repository_name = var.ecr_repo_name
  image_tag       = "latest"
}

resource "aws_lambda_function" "lambda" {
  depends_on = [null_resource.build_and_push]

  function_name = var.function_name
  role          = var.role
  publish       = true
  package_type  = "Image"
  memory_size   = var.memory_size
  timeout       = var.timeout
  handler       = var.handler
  source_code_hash = trimprefix(data.aws_ecr_image.image.id, "sha256:")

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = var.security_group_ids
  }

  environment {
    variables = var.env
  }

  image_uri = format("%s:latest", aws_ecr_repository.ecr_repo.repository_url)
  
  image_config {
    command     = var.command
    entry_point = var.entry_point
  }

}

module "http" {
  source               = "github.com/kperson/terraform-modules//lambda-http-api"
  api_id               = var.api_id
  api_root_resource_id = var.api_root_resource_id
  authorization        = var.authorization
  authorizer_id        = var.authorizer_id
  api_key_required     = var.api_key_required
  authorization_scopes = var.authorization_scopes
  stage_name           = var.stage_name
  lambda_arn           = aws_lambda_function.lambda.arn
}

output "stage" {
  value = module.http.stage
}

variable "image_uri" {
  type = string
}

variable "ecr_repo_name" {
  type = string
}

variable "ecr_repo_tag" {
  type    = string
  default = "latest"
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

resource "null_resource" "build_and_push" {
  triggers = {
    time = timestamp()
  }

  provisioner "local-exec" {

    command = format(
      "docker login --username %s --password %s %s && docker tag %s %s:%s && docker push %s:%s && docker rmi %s:%s && docker logout %s",
      data.aws_ecr_authorization_token.ecr_token.user_name,
      data.aws_ecr_authorization_token.ecr_token.password,
      data.aws_ecr_authorization_token.ecr_token.proxy_endpoint,
      var.image_uri,
      aws_ecr_repository.ecr_repo.repository_url,
      var.ecr_repo_tag,
      aws_ecr_repository.ecr_repo.repository_url,
      var.ecr_repo_tag,
      aws_ecr_repository.ecr_repo.repository_url,
      var.ecr_repo_tag,
      data.aws_ecr_authorization_token.ecr_token.proxy_endpoint
    )
    environment = {
    }
  }
}

# output "image_uri" {
#   depends_on = [null_resource.build_and_push]
#   value      = replace(format("%s%s", var.image_uri, aws_ecr_repository.ecr_repo.repository_url), aws_ecr_repository.ecr_repo.repository_url, "")
# }

# output "ecr_repository_url" {
#   depends_on = [null_resource.build_and_push]
#   value      = format("%s", aws_ecr_repository.ecr_repo.repository_url)
# }

# output "ecr_repo_name" {
#   depends_on = [null_resource.build_and_push]
#   value      = replace(format("%s%s", var.ecr_repo_name, aws_ecr_repository.ecr_repo.repository_url), aws_ecr_repository.ecr_repo.repository_url, "")
# }

# output "ecr_repo_tag" {
#   depends_on = [null_resource.build_and_push]
#   value      = replace(format("%s%s", var.ecr_repo_tag, aws_ecr_repository.ecr_repo.repository_url), aws_ecr_repository.ecr_repo.repository_url, "")
# }


output "image_uri" {
  depends_on = [null_resource.build_and_push]
  value      = var.image_uri
}

output "ecr_repository_url" {
  depends_on = [null_resource.build_and_push]
  value      = aws_ecr_repository.ecr_repo.repository_url
}

output "ecr_repo_name" {
  depends_on = [null_resource.build_and_push]
  value      = var.ecr_repo_name
}

output "ecr_repo_tag" {
  depends_on = [null_resource.build_and_push]
  value      = var.ecr_repo_tag
}
# Task Role
data "aws_iam_policy_document" "assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    principals {
      type        = "Service"
      identifiers = ["dms.us-east-1.amazonaws.com"]
    }
  }
}


resource "aws_iam_role" "lambda" {
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
  name               = "localstack"
}


#hack, we need to wait until the attachements are complete
module "lambda_role_arn" {
  source = "github.com/kperson/terraform-modules//echo"
  in     = []
  out    = aws_iam_role.lambda.arn
}

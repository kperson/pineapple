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

data "aws_iam_policy_document" "log" {

  statement {
    actions = [
      "logs:*",
    ]

    resources = [
      "*",
    ]
  }

}

resource "aws_iam_policy" "log" {
  policy = data.aws_iam_policy_document.log.json
}

resource "aws_iam_role" "lambda" {
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
  name               = "localstack"
}


module "log_role_attatchment" {
  source     = "github.com/kperson/terraform-modules//aws_role_attachment"
  role       = aws_iam_role.lambda.name
  policy_arn = aws_iam_policy.log.arn
}


#hack, we need to wait until the attachements are complete
module "lambda_role_arn" {
  source = "github.com/kperson/terraform-modules//echo"
  in     = [module.log_role_attatchment.role]
  out    = aws_iam_role.lambda.arn
}

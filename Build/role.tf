data "aws_iam_policy_document" "assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
  name               = "pineappletest"
}

#hack, we need to wait until the attachements are complete to do anything
module "lambda_role_arn" {
  source = "github.com/kperson/terraform-modules//echo"
  in = [
    module.log_role_attatchment.role,
    module.test_queue_role_attatchment.role,
    module.db_verify_policy_role_attachement.role
  ]
  out = aws_iam_role.lambda.arn
}
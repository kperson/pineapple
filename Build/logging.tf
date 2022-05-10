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

module "log_role_attatchment" {
  source     = "github.com/kperson/terraform-modules//aws_role_attachment"
  role       = aws_iam_role.lambda.name
  policy_arn = aws_iam_policy.log.arn
}
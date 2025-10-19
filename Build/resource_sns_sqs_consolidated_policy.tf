data "aws_iam_policy_document" "sns_sqs_consolidated" {
  # SNS permissions
  statement {
    actions = [
      "sns:Publish"
    ]
    resources = [
      aws_sns_topic.test_topic.arn
    ]
  }

  # SQS permissions
  statement {
    actions = [
      "sqs:*"
    ]
    resources = [
      aws_sqs_queue.test_queue.arn
    ]
  }
}

resource "aws_iam_policy" "sns_sqs_consolidated" {
  name   = "pineapple-sns-sqs-consolidated-policy"
  policy = data.aws_iam_policy_document.sns_sqs_consolidated.json
}

module "sns_sqs_consolidated_role_attachment" {
  source     = "github.com/kperson/terraform-modules//aws_role_attachment"
  role       = aws_iam_role.lambda.name
  policy_arn = aws_iam_policy.sns_sqs_consolidated.arn
}

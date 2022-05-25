resource "aws_sns_topic" "test_topic" {
  name = "pineapple-test-topic"
}

data "aws_iam_policy_document" "test_topic" {
  statement {
    actions = [
      "sns:Publish"
    ]
    resources = [
        aws_sns_topic.test_topic.arn
    ]
  }
}
resource "aws_iam_policy" "test_topic" {
  policy = data.aws_iam_policy_document.test_topic.json
}

module "test_topic_role_attatchment" {
  source     = "github.com/kperson/terraform-modules//aws_role_attachment"
  role       = aws_iam_role.lambda.name
  policy_arn = aws_iam_policy.test_topic.arn
}


output "test_topic_arn" {
  value = aws_sns_topic.test_topic.arn
}

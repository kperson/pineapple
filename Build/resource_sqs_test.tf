resource "aws_sqs_queue" "test_queue" {
  name = "pineapple-test-queue"
}

data "aws_iam_policy_document" "test_queue" {
  statement {
    actions = [
      "sqs:*"
    ]
    resources = [
      aws_sqs_queue.test_queue.arn
    ]
  }
}
resource "aws_iam_policy" "test_queue" {
  policy = data.aws_iam_policy_document.test_queue.json
}

module "test_queue_role_attatchment" {
  source     = "github.com/kperson/terraform-modules//aws_role_attachment"
  role       = aws_iam_role.lambda.name
  policy_arn = aws_iam_policy.test_queue.arn
}

data "aws_iam_policy_document" "dynamo_consolidated" {
  # DynamoDB CRUD operations for all tables
  statement {
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:Query",
      "dynamodb:Scan",
      "dynamodb:BatchGetItem",
      "dynamodb:BatchWriteItem"
    ]
    resources = [
      module.db_test.arn,
      module.db_verify.arn,
      module.dynamo_stream.arn,
      "${module.db_test.arn}/index/*",
      "${module.db_verify.arn}/index/*",
      "${module.dynamo_stream.arn}/index/*"
    ]
  }

  # DynamoDB Stream operations for all streams
  statement {
    actions = [
      "dynamodb:GetRecords",
      "dynamodb:GetShardIterator",
      "dynamodb:DescribeStream",
      "dynamodb:ListStreams"
    ]
    resources = [
      module.db_test.stream_arn,
      module.db_verify.stream_arn,
      module.dynamo_stream.stream_arn
    ]
  }
}

resource "aws_iam_policy" "dynamo_consolidated" {
  name   = "pineapple-dynamo-consolidated-policy"
  policy = data.aws_iam_policy_document.dynamo_consolidated.json
}

module "dynamo_consolidated_role_attachment" {
  source     = "github.com/kperson/terraform-modules//aws_role_attachment"
  role       = aws_iam_role.lambda.name
  policy_arn = aws_iam_policy.dynamo_consolidated.arn
}

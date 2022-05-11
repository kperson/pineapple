resource "aws_sns_topic" "test_topic" {
  name = "pineapple-test-topic"
}

output "test_topic_arn" {
  value = aws_sns_topic.test_topic.arn
}
resource "aws_sqs_queue" "test_queue" {
  name = "pineapple-test-queue"
}

output "test_queue_url" {
  value = aws_sqs_queue.test_queue.url
}

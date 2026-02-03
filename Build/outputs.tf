# Outputs for SystemTests environment variables

output "verify_table_name" {
  description = "DynamoDB verification table name (for VERIFY_TABLE)"
  value       = module.db_verify.id
}

output "sqs_queue_url" {
  description = "SQS queue URL (for TEST_SQS_QUEUE_URL)"
  value       = aws_sqs_queue.test_queue.url
}

output "sns_topic_arn" {
  description = "SNS topic ARN (for TEST_SNS_TOPIC_ARN)"
  value       = aws_sns_topic.test_topic.arn
}

output "s3_bucket_name" {
  description = "S3 bucket name (for TEST_S3_BUCKET)"
  value       = aws_s3_bucket.test_bucket.id
}

output "dynamo_stream_table_name" {
  description = "DynamoDB stream table name (for TEST_TABLE)"
  value       = module.dynamo_stream.id
}

output "api_gateway_endpoint" {
  description = "API Gateway endpoint URL (for TEST_API_ENDPOINT)"
  value       = module.http_test.endpoint
}

output "test_run_key" {
  description = "Test run key for coordination (for TEST_RUN_KEY)"
  value       = var.test_run_key
}

output "aws_region" {
  description = "AWS region being used"
  value       = var.aws_region
}

# Helper output for setting all environment variables at once
output "systemtest_env_vars" {
  description = "All environment variables for SystemTests (copy-paste ready)"
  value       = <<-EOT
    # Copy and paste these to run SystemTests:
    export TEST_RUN_KEY=${var.test_run_key}
    export VERIFY_TABLE=${module.db_verify.id}
    export TEST_SQS_QUEUE_URL=${aws_sqs_queue.test_queue.url}
    export TEST_SNS_TOPIC_ARN=${aws_sns_topic.test_topic.arn}
    export TEST_S3_BUCKET=${aws_s3_bucket.test_bucket.id}
    export TEST_TABLE=${module.dynamo_stream.id}
    export TEST_API_ENDPOINT=${module.http_test.endpoint}
    
    # Note: AWS_PROFILE is already set in your environment or use the same credentials as Terraform
  EOT
}

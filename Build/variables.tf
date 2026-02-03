variable "aws_region" {
  description = "AWS region for resources (can also use AWS_REGION env var)"
  type        = string
  default     = "us-east-1"
}

variable "test_run_key" {
  description = "Unique identifier for test runs (used by Lambda and SystemTests)"
  type        = string
  default     = "integration-test"
}

variable "log_level" {
  description = "Lambda logging level (trace, debug, info, warning, error)"
  type        = string
  default     = "debug"
}

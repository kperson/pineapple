resource "aws_s3_bucket" "test_bucket" {
  bucket = "pineapple-test"
}

output "test_s3_bucket" {
  value = aws_s3_bucket.test_bucket.id
}

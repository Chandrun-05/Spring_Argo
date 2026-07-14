variable "bucket_name" {}
variable "lambda_role_arn" {}

provider "aws" { region = "us-east-1" }

resource "aws_s3_bucket_policy" "cross_account" {
  bucket = var.bucket_name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowCrossAccountLambda"
      Effect    = "Allow"
      Principal = { AWS = var.lambda_role_arn }
      Action    = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
      Resource  = [
        "arn:aws:s3:::${var.bucket_name}",
        "arn:aws:s3:::${var.bucket_name}/*"
      ]
    }]
  })
}

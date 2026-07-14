variable "target_bucket_name" {}
variable "region" { default = "us-east-1" }

provider "aws" { region = var.region }

data "aws_s3_bucket" "target" {
  bucket = var.target_bucket_name
}

resource "aws_iam_role" "lambda_role" {
  name = "cf-test-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "s3_access" {
  role = aws_iam_role.lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
      Resource = [
        data.aws_s3_bucket.target.arn,
        "${data.aws_s3_bucket.target.arn}/*"
      ]
    }]
  })
}

resource "aws_lambda_function" "test_fn" {
  function_name = "cf-crossacct-test-fn"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler"
  runtime       = "python3.11"
  filename      = "lambda.zip"
}

output "lambda_role_arn" { value = aws_iam_role.lambda_role.arn }

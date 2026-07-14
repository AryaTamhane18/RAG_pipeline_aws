terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

data "aws_caller_identity" "current" {}

data "aws_iam_role" "lab" {
  name = "LabRole"
}

locals {
  ingest_function_name = "capstone-rag-ingest"
  query_function_name  = "capstone-rag-query"
  gemini_secret_name    = "capstone/gemini-api-key"
  table_name            = "capstone-rag-chunks"
}

resource "aws_secretsmanager_secret" "gemini_key" {
  name        = local.gemini_secret_name
  description = "Google Gemini API key. Set the value out of band; never in Terraform."
}

resource "aws_dynamodb_table" "chunks" {
  name         = local.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "doc_id"
  range_key    = "chunk_id"

  attribute {
    name = "doc_id"
    type = "S"
  }
  attribute {
    name = "chunk_id"
    type = "S"
  }

  tags = {
    Project = "capstone-rag"
    Phase   = "2"
  }
}

data "archive_file" "ingest_handler" {
  type        = "zip"
  source_file = "${path.module}/src/ingest_handler.py"
  output_path = "${path.module}/build/ingest_handler.zip"
}

data "archive_file" "query_handler" {
  type        = "zip"
  source_file = "${path.module}/src/query_handler.py"
  output_path = "${path.module}/build/query_handler.zip"
}

resource "aws_lambda_function" "ingest" {
  function_name    = local.ingest_function_name
  role             = data.aws_iam_role.lab.arn
  runtime          = "python3.12"
  handler          = "ingest_handler.lambda_handler"
  timeout          = 30
  memory_size      = 256
  filename         = data.archive_file.ingest_handler.output_path
  source_code_hash = data.archive_file.ingest_handler.output_base64sha256

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.chunks.name
    }
  }
}

resource "aws_lambda_function" "query" {
  function_name    = local.query_function_name
  role             = data.aws_iam_role.lab.arn
  runtime          = "python3.12"
  handler          = "query_handler.lambda_handler"
  timeout          = 30
  memory_size      = 256
  filename         = data.archive_file.query_handler.output_path
  source_code_hash = data.archive_file.query_handler.output_base64sha256

  environment {
    variables = {
      GEMINI_SECRET_NAME = aws_secretsmanager_secret.gemini_key.name
      TABLE_NAME          = aws_dynamodb_table.chunks.name
    }
  }
}

resource "aws_apigatewayv2_api" "http_api" {
  name          = "capstone-rag-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "ingest" {
  api_id                 = aws_apigatewayv2_api.http_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.ingest.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_integration" "query" {
  api_id                 = aws_apigatewayv2_api.http_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.query.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "upload" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "POST /upload"
  target    = "integrations/${aws_apigatewayv2_integration.ingest.id}"
}

resource "aws_apigatewayv2_route" "ask" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "POST /ask"
  target    = "integrations/${aws_apigatewayv2_integration.query.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "apigw_ingest" {
  statement_id  = "AllowAPIGatewayInvokeIngest"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ingest.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "apigw_query" {
  statement_id  = "AllowAPIGatewayInvokeQuery"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.query.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}

resource "aws_cloudwatch_log_group" "ingest_logs" {
  name              = "/aws/lambda/capstone-rag-ingest"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "query_logs" {
  name              = "/aws/lambda/capstone-rag-query"
  retention_in_days = 7
}

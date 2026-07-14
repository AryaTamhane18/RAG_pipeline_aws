output "lambda_function_name" {
  value = aws_lambda_function.rag_ingest.function_name
}

output "lambda_role_arn" {
  value = aws_lambda_function.rag_ingest.role
}

output "secret_arn" {
  value = aws_secretsmanager_secret.gemini_key.arn
}

output "api_endpoint" {
  value = "${aws_apigatewayv2_stage.default_stage.invoke_url}/ask"
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.rag_records.name
}

output "cloudwatch_log_group" {
  value = aws_cloudwatch_log_group.lambda_logs.name
}
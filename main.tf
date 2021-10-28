#####
# AWS provider
#####

# Retrieve AWS credentials from env variables AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY
provider "aws" {
  region = var.aws_region
}

#####
# IAM role
#####

data "template_file" "policy_json" {
  template = "${file("${path.module}/template/policy.json.tpl")}"
  vars = {}
}

resource "aws_iam_policy" "iam_role_policy" {
  name        = "${var.lambda_name}-tagging-lambda"
  path        = "/"
  description = "Policy for role ${var.lambda_name}-tagging-lambda"
  policy      = data.template_file.policy_json.rendered
}

resource "aws_iam_role" "iam_role" {
  name = "${var.lambda_name}-tagging-lambda"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_policy_attachment" "lambda-attach" {
  name       = "${var.lambda_name}-tagging-lambda-attachment"
  roles      = ["${aws_iam_role.iam_role.name}"]
  policy_arn = aws_iam_policy.iam_role_policy.arn
}

#####
# Lambda Function
#####

# Generate ZIP archive with Lambda

data "template_file" "lambda" {
    template = "${file("${path.module}/template/tagging_lambda.py.tpl")}"
    
    vars = {
      aws_region = var.aws_region
      name = var.lambda_name
      search_tag_key = var.search_tag_key
      search_tag_value = var.search_tag_value
      tags = "${jsonencode(var.tags)}"
      timestamp = "${timestamp()}"
    }
}

resource "local_file" "lambda_code" {
  content  = data.template_file.lambda.rendered
  filename = "${path.module}/template/tagging_lambda.py"
}

data "archive_file" "lambda_code" {
  type        = "zip"
  source_file = "${path.module}/template/tagging_lambda.py"
  output_path = "${path.module}/template/tagging_lambda.zip"

    depends_on = [
    local_file.lambda_code
  ]
}


# Create lambda

resource "aws_lambda_function" "tagging" {
  depends_on       = [aws_iam_role.iam_role, data.archive_file.lambda_code]

  filename         = "${path.module}/template/tagging_lambda.zip"
  function_name    = "${var.lambda_name}-tagging-lambda"
  role             = aws_iam_role.iam_role.arn
  source_code_hash = data.archive_file.lambda_code.output_base64sha256
  handler          = "tagging_lambda.lambda_handler"
  runtime          = "python3.8"
  timeout          = "60"
  memory_size      = "128"

  tags = var.tags
}

resource "aws_cloudwatch_event_rule" "tagging" {
  name        = "${var.lambda_name}-tagging-lambda"
  description = "Trigger tagging lambda in periodical intervals"
  schedule_expression = "rate(5 minutes)"
}

resource "aws_lambda_permission" "tagging" {
  statement_id   = "${var.lambda_name}-AllowCloudWatchTrigger"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.tagging.function_name
  principal      = "events.amazonaws.com"
  source_arn     = aws_cloudwatch_event_rule.tagging.arn
}

resource "aws_cloudwatch_event_target" "tagging" {
  rule      = aws_cloudwatch_event_rule.tagging.name
  target_id = "${var.lambda_name}-TriggerLambda"
  arn       = aws_lambda_function.tagging.arn
}
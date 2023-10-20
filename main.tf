###############
#     IAM     #
###############
resource "aws_iam_role" "iam_for_lambda" {
  name               = "iam_for_lambda"
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

# NOTE: We are deleteing the logs:CreateLogGroup action since we are creating a log group resource in terraform
data "aws_iam_policy_document" "lambda_logs" {
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      "arn:aws:logs:*:*:*"
    ]
  }
  statement {
    actions = [
      "xray:PutTraceSegments",
      "xray:PutTelemetryRecords",
    ]
    resources = [
      "arn:aws:xray:*:*:*"
    ]
  }
}

# IAM policy for logging from a lambda
resource "aws_iam_policy" "iam_policy_for_lambda" {
  name        = "aws_iam_policy_for_terraform_aws_lambda_log_role"
  path        = "/"
  description = "AWS IAM Policy for managing aws lambda role"
  policy      = data.aws_iam_policy_document.lambda_logs.json
}

# Policy Attachment on the role.
resource "aws_iam_role_policy_attachment" "attach_iam_policy_to_iam_role" {
  role       = aws_iam_role.iam_for_lambda.name
  policy_arn = aws_iam_policy.iam_policy_for_lambda.arn
}


###############
#   Lambda    #
###############
data "archive_file" "python_lambda_package" {
  type        = "zip"
  source_file = "${path.module}/src/handler.py"
  output_path = "lambda.zip"
}

resource "aws_lambda_function" "lambda" {
  function_name    = var.function_name
  filename         = "lambda.zip"
  description      = "Dumb lambda function utilizing x-ray tracing layer"
  source_code_hash = data.archive_file.python_lambda_package.output_base64sha256
  role             = aws_iam_role.iam_for_lambda.arn
  runtime          = "python3.8"
  handler          = "handler.lambda_handler"
  timeout          = 10
  layers           = [aws_lambda_layer_version.xray.arn]
  depends_on = [
    aws_cloudwatch_log_group.lambda_logs
  ]
  tracing_config {
    mode = "Active"
  }
}

###############
#   Layer     #
###############
resource "aws_lambda_layer_version" "xray" {
  filename            = "${path.module}/layer.zip"
  description         = "aws-xray-sdk module"
  layer_name          = "aws-xray-sdk"
  compatible_runtimes = ["python3.8"]
}

##########################
#   Cloudwatch Logs     #
##########################
# NOTE: The cloudwatch log group HAS to follow this naming convention for lambda logging
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = 14
}

##########################
#   Cloudwatch Alarm     #
##########################
resource "aws_cloudwatch_metric_alarm" "lambda_alarm" {
  alarm_name          = "${var.function_name}-lambda-execution-time"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = "60"
  statistic           = "Maximum"
  threshold           = aws_lambda_function.lambda.timeout * 1000 * 0.75
  alarm_description   = "Lambda Execution Time"
  treat_missing_data  = "ignore"

  insufficient_data_actions = [
    "${aws_sns_topic.alarms.arn}",
  ]

  alarm_actions = [
    "${aws_sns_topic.alarms.arn}",
  ]

  ok_actions = [
    "${aws_sns_topic.alarms.arn}",
  ]

  dimensions = {
    FunctionName = aws_lambda_function.lambda.function_name
  }
}

##########################
#       SNS Topic        #
##########################
resource "aws_sns_topic" "alarms" {
  name = "test-topic"
}

resource "aws_sns_topic_subscription" "subscription" {
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = "jmeisele@yahoo.com"
}

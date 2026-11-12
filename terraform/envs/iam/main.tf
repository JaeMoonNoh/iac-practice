locals {
  envs = ["dev", "staging", "prod"]
}

resource "aws_iam_group" "interns" {
  name = "interns"
}

# 환경마다 "로그 버킷 읽기" 정책을 하나씩 만듦
resource "aws_iam_policy" "app_logs_read" {
  for_each = toset(local.envs)
  name     = "s3-app-logs-${each.key}-read"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = "arn:aws:s3:::app-logs-${each.key}"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "arn:aws:s3:::app-logs-${each.key}/*"
      }
    ]
  })
}

resource "aws_iam_group_policy_attachment" "interns_app_logs_read" {
  group      = aws_iam_group.interns.name
  policy_arn = aws_iam_policy.app_logs_read["dev"].arn
}


resource "aws_iam_user_group_membership" "park_intern" {
  user   = "park.intern"
  groups = [aws_iam_group.interns.name]
}

# 기존 prod 정책은 지우지 말고, 환경별 정책 중 "prod" 자리로 이사
moved {
  from = aws_iam_policy.s3_app_logs_prod_read
  to   = aws_iam_policy.app_logs_read["prod"]
}

# =====================================================================
# bootstrap — Terraform state 를 저장할 S3 버킷을 만드는 스택
# ---------------------------------------------------------------------
# [닭과 달걀 문제]
#   envs/local 의 state 를 S3 에 두려면, terraform init 전에 버킷이 이미 있어야 합니다.
#   그런데 그 버킷도 코드로 관리하고 싶습니다.
#   → 버킷만 만드는 이 작은 스택을 따로 두고, 이 스택의 state 는 "로컬 파일"로 둡니다.
#
# 실무에서는 계정당 1번 실행하고 거의 건드리지 않습니다.
# (조직에 따라 이 bootstrap state 도 나중에 S3 로 옮기거나, CloudFormation 으로 만들기도 합니다)
# =====================================================================

provider "aws" {
  region     = var.aws_region
  access_key = "test"
  secret_key = "test"

  allowed_account_ids = ["000000000000"]

  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
  s3_use_path_style           = true

  endpoints {
    s3  = var.aws_endpoint
    sts = var.aws_endpoint
  }

  default_tags {
    tags = {
      Project   = "iac-practice"
      ManagedBy = "terraform"
      Stack     = "bootstrap"
    }
  }
}

variable "aws_region" {
  description = "state 버킷 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "aws_endpoint" {
  description = "Floci 엔드포인트"
  type        = string
  default     = "http://localhost:4566"

  validation {
    condition     = can(regex("^http://(localhost|127\\.0\\.0\\.1|floci)(:[0-9]+)?$", var.aws_endpoint))
    error_message = "aws_endpoint 는 로컬 주소만 허용됩니다."
  }
}

variable "state_bucket_name" {
  description = "state 버킷 이름. S3 버킷 이름은 전 세계에서 유일해야 해서 실무에서는 계정 ID 등을 붙입니다."
  type        = string
  default     = "iac-practice-tfstate"
}

# ---------------------------------------------------------------------
# state 버킷: state 에는 모든 리소스 ID 와 민감값이 평문으로 들어가므로 4중으로 보호합니다.
# ---------------------------------------------------------------------
resource "aws_s3_bucket" "state" {
  bucket = var.state_bucket_name

  # 실수로 terraform destroy 해도 이 버킷은 지워지지 않게 막습니다.
  # (state 를 잃으면 Terraform 은 자기가 만든 인프라를 전부 "모르는 것"으로 취급하게 됩니다)
  lifecycle {
    prevent_destroy = true
  }
}

# ① 버전 관리: state 가 깨지거나 잘못 덮어써져도 이전 버전으로 되돌릴 수 있습니다.
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# ② 저장 시 암호화
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ③ 퍼블릭 접근 전면 차단
resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ④ ACL 비활성화: 객체 소유권을 버킷 소유자로 강제 (AWS 현재 권장 기본값)
resource "aws_s3_bucket_ownership_controls" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

output "state_bucket" {
  description = "envs/*/backend.tf 의 bucket 값"
  value       = aws_s3_bucket.state.bucket
}

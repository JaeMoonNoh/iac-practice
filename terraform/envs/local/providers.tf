# =====================================================================
# providers.tf — Terraform이 "어디에, 어떤 자격으로" API를 호출할지
# ---------------------------------------------------------------------
# 실제 AWS에서는 이 블록이 region 한 줄 정도로 짧습니다.
# 에뮬레이터를 쓰기 때문에 아래 설정들이 추가로 필요합니다.
# =====================================================================

locals {
  # 앞으로 사용할 AWS 서비스 목록. 새 서비스를 쓰게 되면 여기에 추가합니다.
  # (Floci 공식 가이드: "사용하는 모든 서비스마다 endpoint를 지정해야 한다")
  emulated_services = [
    "ec2", "iam", "sts", "s3", "kms",
    "secretsmanager", "ssm", "rds", "elbv2", "ecr",
    "dynamodb", "cloudwatch", "logs",
  ]
}

provider "aws" {
  region = var.aws_region

  # 가짜 자격증명. Floci는 비어있지 않은 아무 값이나 받아줍니다.
  # 일부러 코드에 박아두는 이유: 셸에 회사 AWS 자격증명이 있어도
  # 이 provider는 절대 그걸 쓰지 않도록 하기 위함입니다. (안전장치 1)
  access_key = "test"
  secret_key = "test"

  # 안전장치 2: 이 계정 ID가 아니면 plan/apply 자체를 거부합니다.
  # 실무에서도 "prod 코드로 dev 계정을 건드리는 사고"를 막기 위해 쓰는 설정입니다.
  # 000000000000 은 에뮬레이터의 기본 계정 ID입니다.
  allowed_account_ids = ["000000000000"]

  # 에뮬레이터는 진짜 AWS 인증 서버/메타데이터 서버가 없으므로 검사를 건너뜁니다.
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_region_validation      = true

  # S3 버킷 주소를 bucket.localhost 대신 localhost/bucket 형태로 호출
  s3_use_path_style = true

  # 서비스별 API 주소를 모두 Floci로 돌립니다.
  # endpoints 는 반복문으로 생성할 수 없어서 서비스마다 한 줄씩 적습니다.
  # 새 서비스를 쓸 때는 여기와 위 locals 목록 두 곳에 추가하세요.
  endpoints {
    ec2            = var.aws_endpoint
    iam            = var.aws_endpoint
    sts            = var.aws_endpoint
    s3             = var.aws_endpoint
    kms            = var.aws_endpoint
    secretsmanager = var.aws_endpoint
    ssm            = var.aws_endpoint
    rds            = var.aws_endpoint
    elbv2          = var.aws_endpoint
    ecr            = var.aws_endpoint
    dynamodb       = var.aws_endpoint
    cloudwatch     = var.aws_endpoint
    logs           = var.aws_endpoint
  }

  # 이 provider로 만드는 "모든" 리소스에 자동으로 붙는 태그.
  # 실무에서 비용 추적·소유자 파악의 기본입니다.
  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = "github.com/JaeMoonNoh/iac-practice"
    }
  }
}

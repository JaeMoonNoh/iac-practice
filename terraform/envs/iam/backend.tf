# =====================================================================
# backend.tf — state 를 "어디에" 저장할지
# ---------------------------------------------------------------------
# 이 블록이 없으면 state 는 이 폴더의 terraform.tfstate 파일(로컬)에 저장됩니다.
# 로컬 state 의 문제:
#   - 내 Mac 에만 있음 → 다른 사람/CI 가 같은 인프라를 관리할 수 없음
#   - 디스크가 날아가면 Terraform 이 자기가 만든 인프라를 잊어버림
#   - 두 사람이 동시에 apply 하면 state 가 꼬임
#
# S3 backend + use_lockfile:
#   - state 를 S3 버킷(버전관리·암호화)에 저장
#   - plan/apply 하는 동안 "<key>.tflock" 파일을 만들어 다른 실행을 막음 (Terraform 1.10+)
#     (예전에는 DynamoDB 테이블로 잠갔지만 지금은 S3 만으로 가능 → DynamoDB 방식은 deprecated)
#
# 주의: backend 블록에는 변수(var.*)를 쓸 수 없습니다. 값이 전부 고정 문자열이어야 합니다.
#       (init 시점에 변수 평가보다 먼저 읽히기 때문)
# =====================================================================
terraform {
  backend "s3" {
    bucket       = "iac-practice-tfstate" # terraform/bootstrap 이 만든 버킷
    key          = "envs/iam/terraform.tfstate"
    region       = "ap-northeast-2"
    encrypt      = true
    use_lockfile = true

    # ---- 아래는 Floci(에뮬레이터) 때문에 필요한 설정. 실제 AWS 에서는 지웁니다. ----
    endpoints = {
      s3  = "http://localhost:4566"
      sts = "http://localhost:4566"
    }
    access_key                  = "test"
    secret_key                  = "test"
    use_path_style              = true
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
  }
}

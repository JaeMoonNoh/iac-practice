# =====================================================================
# envs/iam — IAM(그룹, 정책)을 "처음부터 코드로" 만드는 실습 환경
# ---------------------------------------------------------------------
# state 는 network(envs/local), brownfield 와 분리되어 있습니다. (backend.tf 의 key)
# 권한은 사고가 나면 영향이 크기 때문에, 실무에서도 IAM 은 별도 state 로 두는 경우가 많습니다.
# =====================================================================
provider "aws" {
  region     = "ap-northeast-2"
  access_key = "test"
  secret_key = "test"

  allowed_account_ids = ["000000000000"]

  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
  s3_use_path_style           = true

  endpoints {
    iam = "http://localhost:4566"
    sts = "http://localhost:4566"
    s3  = "http://localhost:4566"
  }

  default_tags {
    tags = {
      ManagedBy = "terraform"
      Project   = "iac-practice"
    }
  }
}

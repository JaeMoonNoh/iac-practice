# =====================================================================
# envs/brownfield — "콘솔로 만들어진 기존 리소스"를 Terraform 관리로 가져오는 환경
# ---------------------------------------------------------------------
# envs/local(1단계 네트워크)과 state 를 분리했습니다. (backend.tf 의 key 가 다름)
# 실무에서도 "새로 만든 것"과 "가져온 것"은 state 를 나눠서, 사고가 나도 영향 범위를 줄입니다.
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
    ec2 = "http://localhost:4566"
    iam = "http://localhost:4566"
    sts = "http://localhost:4566"
    s3  = "http://localhost:4566"
  }

  # [주의] 가져온(import) 리소스에도 이 태그가 "추가"됩니다.
  #   → import 직후 plan 에 "~ tags_all + ManagedBy = terraform" 같은 변경이 보이는 이유.
  #   실무에서는 이 태그가 "이제 Terraform 이 관리하는 리소스"라는 표시가 되므로 보통 그대로 둡니다.
  default_tags {
    tags = {
      ManagedBy = "terraform"
      Project   = "iac-practice"
    }
  }
}

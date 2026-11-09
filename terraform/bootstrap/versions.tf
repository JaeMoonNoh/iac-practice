# =====================================================================
# versions.tf — "이 코드는 어떤 버전의 Terraform/Provider로 돌려야 하는가"
# ---------------------------------------------------------------------
# required_version : Terraform 본체 버전 제약
# required_providers: 플러그인(provider) 출처와 버전 제약
#
# "~> 6.0" 은 6.x 는 허용, 7.0 은 불허라는 뜻 (pessimistic constraint).
# 메이저 버전은 breaking change가 있으므로 막아두는 게 실무 관례입니다.
# 실제로 설치된 정확한 버전은 .terraform.lock.hcl 에 기록되고, 그 파일은 Git에 커밋합니다.
# =====================================================================
terraform {
  required_version = ">= 1.10, < 2.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

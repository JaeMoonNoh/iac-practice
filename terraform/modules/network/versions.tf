# 모듈도 자신이 필요로 하는 provider와 최소 버전을 선언합니다.
# provider "aws" { ... } 설정 블록은 모듈 안에 두지 않습니다.
# → 설정(리전, 엔드포인트, 자격증명)은 호출하는 쪽(envs/*)이 결정하고 모듈은 재사용만 됩니다.
terraform {
  required_version = ">= 1.10, < 2.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
  }
}

# =====================================================================
# envs/local — 로컬(Floci) 환경의 진입점
# ---------------------------------------------------------------------
# envs/* 는 "조립"만 합니다. 실제 리소스 정의는 modules/* 에 있고,
# 여기서는 환경별 값(CIDR, NAT 개수 등)을 정해 모듈에 넘깁니다.
# 나중에 envs/prod 를 만들면 같은 모듈에 다른 값만 넘기면 됩니다.
# =====================================================================

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name = "${var.project}-${var.environment}"

  # 서울 리전 a, c 를 사용 (b 는 일부 인스턴스 타입이 없어서 실무에서 자주 제외됨)
  azs = [
    for az in data.aws_availability_zones.available.names : az
    if contains(["a", "c"], substr(az, -1, 1))
  ]
}

module "network" {
  source = "../../modules/network"

  name     = local.name
  vpc_cidr = "10.0.0.0/16"
  azs      = local.azs

  # 로컬/개발 환경: NAT 1개로 비용 절감. prod 에서는 false.
  enable_nat_gateway = true
  single_nat_gateway = true
}

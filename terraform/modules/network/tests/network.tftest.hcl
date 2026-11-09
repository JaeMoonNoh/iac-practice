# =====================================================================
# network 모듈 단위 테스트 — `terraform test`
# ---------------------------------------------------------------------
# mock_provider: 진짜 AWS/Floci 를 호출하지 않고 가짜 응답으로 plan 을 계산합니다.
#   → 수 초 안에 끝나고, 인프라 없이 CI 에서 돌릴 수 있습니다.
# command = plan: 리소스를 만들지 않고 "계획된 값"만 검사합니다.
# =====================================================================

mock_provider "aws" {}

variables {
  name = "test"
  azs  = ["ap-northeast-2a", "ap-northeast-2c"]
}

# ---- 1. 기본값: 계층 3개 x AZ 2개 = 서브넷 6개, CIDR 규칙 확인 ----------
run "creates_three_tiers_per_az" {
  command = plan

  assert {
    condition     = length(aws_subnet.this) == 6
    error_message = "서브넷은 3계층 x 2AZ = 6개여야 합니다."
  }

  assert {
    condition     = aws_subnet.this["public/ap-northeast-2a"].cidr_block == "10.0.0.0/24"
    error_message = "public 첫 서브넷 CIDR 이 10.0.0.0/24 가 아닙니다."
  }

  # CIDR 번호는 목록 순서가 아니라 AZ 글자로 결정: c → 2
  assert {
    condition     = aws_subnet.this["app/ap-northeast-2c"].cidr_block == "10.0.12.0/24"
    error_message = "app/2c 서브넷 CIDR 이 10.0.12.0/24 가 아닙니다."
  }

  assert {
    condition     = aws_subnet.this["db/ap-northeast-2a"].cidr_block == "10.0.20.0/24"
    error_message = "db 첫 서브넷 CIDR 이 10.0.20.0/24 가 아닙니다."
  }

  assert {
    condition     = alltrue([for s in aws_subnet.this : s.map_public_ip_on_launch == false])
    error_message = "어떤 서브넷도 공인 IP 자동 할당을 켜면 안 됩니다."
  }
}

# ---- 2. 보안 경계: db 계층에는 인터넷 라우트가 없어야 한다 ---------------
run "db_tier_has_no_internet_route" {
  command = plan

  # db 라우팅 테이블에는 inline route 가 없어야 하고,
  # 0.0.0.0/0 aws_route 는 public 1개 + app(AZ 수)개 뿐이어야 합니다.
  assert {
    condition     = length(aws_route_table_association.db) == 2
    error_message = "db 서브넷 2개가 모두 db 라우팅 테이블에 연결돼야 합니다."
  }

  assert {
    condition     = length(aws_route.app_nat) == 2
    error_message = "NAT 라우트는 app 라우팅 테이블(AZ 2개)에만 존재해야 합니다."
  }

  # route = [] 가 지워지면 수동 추가된 인터넷 라우트를 감지하지 못하게 됩니다. (docs/01-network.md 참고)
  assert {
    condition     = aws_route_table.db.route != null && length(aws_route_table.db.route) == 0
    error_message = "db 라우팅 테이블은 route = [] 를 명시해 라우트를 '없음'으로 관리해야 합니다."
  }
}

# ---- 3. NAT 개수: single / per-AZ / 끄기 --------------------------------
run "single_nat_by_default" {
  command = plan

  assert {
    condition     = length(aws_nat_gateway.this) == 1
    error_message = "기본값(single_nat_gateway=true)이면 NAT 는 1개여야 합니다."
  }
}

run "nat_per_az_for_prod" {
  command = plan

  variables {
    single_nat_gateway = false
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 2
    error_message = "single_nat_gateway=false 면 AZ 마다 NAT 가 있어야 합니다."
  }
}

run "no_nat_when_disabled" {
  command = plan

  variables {
    enable_nat_gateway = false
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 0 && length(aws_route.app_nat) == 0
    error_message = "enable_nat_gateway=false 면 NAT 와 app 인터넷 라우트가 없어야 합니다."
  }
}

# ---- 4. 입력 검증: 잘못된 값은 거부돼야 한다 -----------------------------
run "rejects_single_az" {
  command = plan

  variables {
    azs = ["ap-northeast-2a"]
  }

  # 이 run 은 "실패해야 성공"입니다.
  expect_failures = [var.azs]
}

# ---- 5. 회귀 테스트: AZ 를 추가해도 기존 서브넷 CIDR 은 그대로여야 한다 -----
run "adding_az_keeps_existing_cidrs" {
  command = plan

  variables {
    azs = ["ap-northeast-2a", "ap-northeast-2b", "ap-northeast-2c"]
  }

  assert {
    condition = (
      aws_subnet.this["public/ap-northeast-2c"].cidr_block == "10.0.2.0/24" &&
      aws_subnet.this["app/ap-northeast-2c"].cidr_block == "10.0.12.0/24" &&
      aws_subnet.this["db/ap-northeast-2c"].cidr_block == "10.0.22.0/24"
    )
    error_message = "b 를 추가했더니 c 서브넷 CIDR 이 바뀌었습니다 → 기존 서브넷이 재생성됩니다!"
  }
}

run "rejects_invalid_cidr" {
  command = plan

  variables {
    vpc_cidr = "10.0.0.0/28"
  }

  expect_failures = [var.vpc_cidr]
}

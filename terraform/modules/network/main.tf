# =====================================================================
# network 모듈 — 3계층(3-tier) VPC
# ---------------------------------------------------------------------
#  계층      | 들어갈 것             | 인터넷 inbound | 인터넷 outbound
#  ----------|-----------------------|----------------|----------------
#  public    | ALB, NAT Gateway      | O (IGW)        | O (IGW)
#  app       | EC2 (백엔드)          | X              | O (NAT 경유)
#  db        | RDS                   | X              | X (완전 격리)
#
# 서브넷이 public 인지 private 인지는 "이름"이 아니라 **라우팅 테이블**이 결정합니다.
#   0.0.0.0/0 → IGW 가 있으면 public, 없으면 private.
# =====================================================================

locals {
  # 계층별로 CIDR 블록 번호 구간을 나눠둡니다. (/16 + 8bit → /24 기준)
  #   public: 10.0.0.x ~ 10.0.3.x
  #   app   : 10.0.10.x ~ 10.0.13.x
  #   db    : 10.0.20.x ~ 10.0.23.x
  tier_offsets = {
    public = 0
    app    = 10
    db     = 20
  }

  # AZ 이름 → 번호. **목록 순서가 아니라 AZ 끝 글자**로 정합니다. (a=0, b=1, c=2 ...)
  #   예) ap-northeast-2a → 0, ap-northeast-2c → 2
  # 목록 순서(0,1,2..)로 정하면 azs 를 [a,c] → [a,b,c] 로 바꿀 때 c 의 순번이 1→2 로 밀려
  # c 서브넷 CIDR 이 바뀌고 → 서브넷과 그 안의 EC2/RDS 까지 재생성됩니다. (docs/01-network.md 실습 D)
  az_index   = { for az in var.azs : az => index(local.az_letters, substr(az, -1, 1)) }
  az_letters = ["a", "b", "c", "d", "e", "f"]

  # 계층별 서브넷 정의를 map 으로 생성. 키 예) "app/ap-northeast-2a"
  subnets = merge([
    for tier, offset in local.tier_offsets : {
      for az, i in local.az_index : "${tier}/${az}" => {
        tier = tier
        az   = az
        cidr = cidrsubnet(var.vpc_cidr, var.subnet_newbits, offset + i)
      }
    }
  ]...)

  # NAT 를 둘 AZ 목록. single 이면 첫 번째 AZ 하나만.
  nat_azs = var.enable_nat_gateway ? (var.single_nat_gateway ? [var.azs[0]] : var.azs) : []
}

# ---------------------------------------------------------------------
# VPC
# ---------------------------------------------------------------------
resource "aws_vpc" "this" {
  cidr_block = var.vpc_cidr

  # 둘 다 켜야 VPC 내부에서 RDS 엔드포인트, VPC Endpoint(SSM 등) 의 DNS 이름이 해석됩니다.
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, { Name = "${var.name}-vpc" })
}

# AWS 가 VPC 마다 자동으로 만드는 "기본 SG"는 같은 SG 끼리 모든 트래픽을 허용합니다.
# 실수로 이 SG 가 리소스에 붙는 사고를 막기 위해, 규칙을 전부 비운 상태로 Terraform 이 관리합니다.
# (CIS AWS Benchmark 권고사항: "default security group 은 모든 트래픽을 차단해야 한다")
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-default-sg-deny-all" })
}

# ---------------------------------------------------------------------
# 서브넷 (계층 x AZ)
# ---------------------------------------------------------------------
# count 가 아닌 for_each 를 쓰는 이유:
#   count 는 리소스를 [0], [1], [2] 순번으로 기억합니다. 목록 중간 AZ 하나를 빼면
#   뒤 번호가 당겨지면서 "멀쩡한 서브넷을 삭제 후 재생성"하는 plan 이 나옵니다.
#   for_each 는 "app/ap-northeast-2a" 같은 키로 기억하므로 해당 항목만 영향받습니다.
resource "aws_subnet" "this" {
  for_each = local.subnets

  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value.cidr
  availability_zone = each.value.az

  # public 서브넷도 자동 공인 IP 할당은 끕니다.
  # 공인 IP 가 필요한 리소스(ALB, NAT)는 각자 명시적으로 받습니다.
  map_public_ip_on_launch = false

  tags = merge(var.tags, {
    Name = "${var.name}-${each.value.tier}-${each.value.az}"
    Tier = each.value.tier
  })
}

# ---------------------------------------------------------------------
# Public 라우팅: 0.0.0.0/0 → Internet Gateway
# ---------------------------------------------------------------------
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-igw" })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-public-rt" })
}

# 라우트를 aws_route_table 안의 inline route 블록이 아닌 별도 리소스로 정의합니다.
# 두 방식을 섞으면 서로 덮어쓰며 매번 drift 가 나므로, 실무에서는 한 가지로 통일합니다.
resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  for_each = { for k, s in local.subnets : k => s if s.tier == "public" }

  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.public.id
}

# ---------------------------------------------------------------------
# NAT Gateway: private(app) → 인터넷 outbound 전용 출구
# ---------------------------------------------------------------------
# NAT 는 public 서브넷에 위치하고, 고정 공인 IP(EIP)를 가집니다.
# 외부에서 NAT 로 먼저 연결을 시작할 수는 없습니다 (outbound only).
resource "aws_eip" "nat" {
  for_each = toset(local.nat_azs)

  domain = "vpc"
  tags   = merge(var.tags, { Name = "${var.name}-nat-eip-${each.key}" })

  # IGW 가 없으면 EIP 를 VPC 에 연결할 수 없으므로 순서를 명시
  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  for_each = toset(local.nat_azs)

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.this["public/${each.key}"].id
  tags          = merge(var.tags, { Name = "${var.name}-nat-${each.key}" })
}

# ---------------------------------------------------------------------
# App 라우팅: AZ 마다 라우팅 테이블 1개
# ---------------------------------------------------------------------
# AZ 별로 나누는 이유: single_nat_gateway=false 로 바꾸면 각 AZ 가 자기 AZ 의 NAT 를 쓰도록
# 라우트만 바뀌고, 라우팅 테이블 구조는 그대로 유지됩니다.
resource "aws_route_table" "app" {
  for_each = toset(var.azs)

  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-app-rt-${each.key}" })
}

resource "aws_route" "app_nat" {
  for_each = var.enable_nat_gateway ? toset(var.azs) : toset([])

  route_table_id         = aws_route_table.app[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  # single 이면 모든 AZ 가 첫 번째 AZ 의 NAT 로, 아니면 자기 AZ 의 NAT 로
  nat_gateway_id = aws_nat_gateway.this[var.single_nat_gateway ? var.azs[0] : each.key].id
}

resource "aws_route_table_association" "app" {
  for_each = { for k, s in local.subnets : k => s if s.tier == "app" }

  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.app[each.value.az].id
}

# ---------------------------------------------------------------------
# DB 라우팅: 0.0.0.0/0 라우트 없음 = 완전 격리
# ---------------------------------------------------------------------
# VPC 내부 통신(10.0.0.0/16 → local)은 모든 라우팅 테이블에 자동으로 들어있어서
# app 서브넷의 EC2 → db 서브넷의 RDS 통신은 가능합니다.
resource "aws_route_table" "db" {
  vpc_id = aws_vpc.this.id

  # [중요] route = [] 를 "명시"합니다.
  # 이 줄이 없으면 Terraform 은 이 테이블의 라우트를 관리 대상으로 보지 않습니다.
  # → 누군가 콘솔에서 0.0.0.0/0 → IGW 를 추가해 DB 를 인터넷에 노출시켜도 plan 이 "No changes".
  # 빈 목록을 명시하면 "라우트는 하나도 없어야 한다"가 코드의 의도가 되어,
  # 수동으로 추가된 라우트를 drift 로 감지하고 apply 시 제거합니다.
  # (db 테이블에는 aws_route 리소스를 쓰지 않으므로 inline/별도 리소스 혼용 문제도 없음)
  route = []

  tags = merge(var.tags, { Name = "${var.name}-db-rt" })
}

resource "aws_route_table_association" "db" {
  for_each = { for k, s in local.subnets : k => s if s.tier == "db" }

  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.db.id
}

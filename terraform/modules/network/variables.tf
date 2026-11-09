variable "name" {
  description = "리소스 이름 접두어 (예: iac-practice-local)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{3,32}$", var.name))
    error_message = "name 은 소문자/숫자/하이픈 3~32자여야 합니다."
  }
}

variable "vpc_cidr" {
  description = "VPC 전체 IP 대역. /16 이면 IP 65,536개."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    # cidrhost() 는 올바른 CIDR 이 아니면 에러 → can() 으로 감싸 true/false 로 변환
    condition     = can(cidrhost(var.vpc_cidr, 0)) && tonumber(split("/", var.vpc_cidr)[1]) <= 20
    error_message = "vpc_cidr 는 올바른 CIDR 이어야 하고, 서브넷을 나눌 수 있도록 /20 이상(더 큰 대역)이어야 합니다."
  }
}

variable "azs" {
  description = "서브넷을 배치할 가용영역 목록. 고가용성을 위해 최소 2개."
  type        = list(string)

  validation {
    condition     = length(var.azs) >= 2 && length(var.azs) <= 4
    error_message = "azs 는 2~4개여야 합니다. (1개면 AZ 장애 시 전체가 멈춤)"
  }

  validation {
    # 서브넷 CIDR 번호를 AZ 끝 글자(a~f)로 계산하므로 형식을 강제합니다.
    condition     = alltrue([for az in var.azs : can(regex("^[a-z]{2}-[a-z]+-[0-9][a-f]$", az))])
    error_message = "azs 는 'ap-northeast-2a' 처럼 a~f 로 끝나는 AZ 이름이어야 합니다."
  }
}

variable "subnet_newbits" {
  description = <<-EOT
    VPC CIDR 에서 서브넷을 자를 때 추가할 비트 수.
    /16 VPC + 8 = /24 서브넷 (IP 256개, AWS 예약 5개 제외 251개 사용 가능)
  EOT
  type        = number
  default     = 8
}

variable "enable_nat_gateway" {
  description = "프라이빗(app) 서브넷이 인터넷으로 나가는(outbound) 경로를 만들지 여부"
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = <<-EOT
    true  : NAT 를 1개만 만들어 모든 AZ 가 공유 (비용 절감, dev 용. 해당 AZ 장애 시 전체 outbound 끊김)
    false : AZ 마다 NAT 1개 (prod 권장. NAT 1개당 월 약 $45 + 트래픽 비용)
  EOT
  type        = bool
  default     = true
}

variable "tags" {
  description = "모든 리소스에 추가로 붙일 태그 (provider default_tags 와 병합됨)"
  type        = map(string)
  default     = {}
}

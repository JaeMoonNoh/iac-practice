variable "aws_region" {
  description = "리소스를 만들 리전. 실무와 동일하게 서울 리전을 사용합니다."
  type        = string
  default     = "ap-northeast-2"
}

variable "aws_endpoint" {
  description = "Floci 엔드포인트. 모든 AWS API 호출이 이 주소로 향합니다."
  type        = string
  default     = "http://localhost:4566"

  # 입력값 검증(validation): 잘못된 값이면 plan 단계에서 즉시 실패합니다.
  # 여기서는 "로컬 주소만 허용"해서 실수로 외부 엔드포인트를 쓰는 걸 막습니다.
  validation {
    condition     = can(regex("^http://(localhost|127\\.0\\.0\\.1|floci)(:[0-9]+)?$", var.aws_endpoint))
    error_message = "aws_endpoint 는 로컬 주소(localhost / 127.0.0.1 / floci)만 허용됩니다."
  }
}

variable "project" {
  description = "모든 리소스 이름/태그의 접두어"
  type        = string
  default     = "iac-practice"
}

variable "environment" {
  description = "환경 이름 (local, dev, prod ...)"
  type        = string
  default     = "local"
}

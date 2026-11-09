# tflint: terraform validate가 못 잡는 "관례/실수"를 잡는 린터.
# 0단계는 Terraform 기본 규칙만 사용. AWS 전용 규칙(잘못된 인스턴스 타입 등)은 2단계에서 추가.
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

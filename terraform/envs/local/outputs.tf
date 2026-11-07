output "account_id" {
  description = "에뮬레이터 계정 ID (000000000000 이어야 정상)"
  value       = data.aws_caller_identity.current.account_id
}

output "caller_arn" {
  description = "현재 인증 주체 ARN"
  value       = data.aws_caller_identity.current.arn
}

output "region" {
  description = "현재 리전"
  value       = data.aws_region.current.region
}

output "availability_zones" {
  description = "사용 가능한 AZ 목록"
  value       = data.aws_availability_zones.available.names
}

output "emulated_services" {
  description = "Floci로 라우팅되는 서비스 목록"
  value       = local.emulated_services
}

output "account_id" {
  description = "에뮬레이터 계정 ID (000000000000 이어야 정상)"
  value       = data.aws_caller_identity.current.account_id
}

output "region" {
  description = "현재 리전"
  value       = data.aws_region.current.region
}

output "azs" {
  description = "사용 중인 AZ"
  value       = local.azs
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.network.vpc_id
}

output "subnet_cidrs" {
  description = "계층/AZ 별 CIDR"
  value       = module.network.subnet_cidrs
}

output "public_subnet_ids" {
  value = module.network.public_subnet_ids
}

output "app_subnet_ids" {
  value = module.network.app_subnet_ids
}

output "db_subnet_ids" {
  value = module.network.db_subnet_ids
}

output "nat_public_ips" {
  value = module.network.nat_public_ips
}

# 모듈의 output 은 "다른 모듈이 나를 쓰기 위해 알아야 하는 것"만 공개합니다.
# 다음 단계에서 compute 모듈은 app_subnet_ids 를, database 모듈은 db_subnet_ids 를 받아 씁니다.

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "VPC CIDR (SG 규칙에서 'VPC 내부만 허용' 할 때 사용)"
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "public 서브넷 ID 목록 (AZ 순서) — ALB 용"
  value       = [for az in var.azs : aws_subnet.this["public/${az}"].id]
}

output "app_subnet_ids" {
  description = "app 서브넷 ID 목록 (AZ 순서) — EC2 용"
  value       = [for az in var.azs : aws_subnet.this["app/${az}"].id]
}

output "db_subnet_ids" {
  description = "db 서브넷 ID 목록 (AZ 순서) — RDS 용"
  value       = [for az in var.azs : aws_subnet.this["db/${az}"].id]
}

output "app_route_table_ids" {
  description = "app 라우팅 테이블 ID 목록 — 4단계 VPC Endpoint(S3 Gateway) 연결용"
  value       = [for az in var.azs : aws_route_table.app[az].id]
}

output "nat_public_ips" {
  description = "NAT 공인 IP — 외부 API 가 IP 화이트리스트를 요구할 때 전달하는 값"
  value       = [for eip in aws_eip.nat : eip.public_ip]
}

output "subnet_cidrs" {
  description = "계층/AZ 별 CIDR (확인용)"
  value       = { for k, s in local.subnets : k => s.cidr }
}

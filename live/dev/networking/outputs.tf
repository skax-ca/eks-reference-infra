# 이 루트의 출력은 하류 루트가 참조할 앵커를 노출하고, 모듈 출력 계약이 실제로 소비되는지
# 보인다(단순 재노출이 아니라 map 키 접근까지 해야 계약이 동작함이 증명된다).
#
# ⚠️ 하류가 다른 배포 루트라면 remote state 참조가 아니라 Name 태그 data source 조회를 쓴다.
#    이 출력들은 그 대안이 아니라 "계약이 살아 있다"의 증거다.

output "vpc_id" {
  description = "생성된 VPC ID."
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "VPC primary CIDR. 인프라 전용 소형 대역이고 워크로드는 secondary에 있다."
  value       = module.vpc.vpc_cidr_block
}

output "secondary_cidr_blocks" {
  description = <<-EOT
    연결이 완료된 secondary CIDR 목록. 값이 2개(uniq·dup)로 나오는 것이 secondary CIDR
    depends_on 순서와 primary/secondary 조합 제약이 성립한다는 증거다.
  EOT
  value       = module.vpc.secondary_cidr_blocks
}

output "subnet_ids_by_group" {
  description = "그룹 키 → 서브넷 ID 리스트(AZ 순서). 키는 이 루트가 넘긴 subnet_groups 키 그대로다."
  value       = module.vpc.subnet_ids_by_group
}

# 소비자가 실제로 하는 일: 자기가 준 키로 되받아 하류 모듈에 넘긴다. 모듈이 키를 변형하지
# 않기 때문에 이 접근이 예측 가능하다.
output "eks_node_subnet_ids" {
  description = "EKS 노드를 놓을 private 서브넷 ID. EKS 배포 루트에 그대로 넘기는 형태다."
  value       = module.vpc.subnet_ids_by_group["node-uniq"]
}

output "eks_pod_subnet_ids" {
  description = "EKS Pod 전용 서브넷 ID(ENIConfig용). dup 대역이라 온프레미스로 라우팅되지 않는다."
  value       = module.vpc.subnet_ids_by_group["pod-dup"]
}

# 운영 라우트의 앵커. hub 방향 라우트는 main.tf의 aws_route.to_hub가 이 RT에 얹는다.
output "route_table_ids_by_group" {
  description = "그룹 키 → 라우팅 테이블 ID. 운영 라우트(온프레미스→TGW 등)를 추가할 앵커다."
  value       = module.vpc.route_table_ids_by_group
}

output "nat_gateway_ids" {
  description = "NAT Gateway ID. single_nat_gateway = true이므로 1개다."
  value       = module.vpc.nat_gateway_ids
}

output "flow_log_group_name" {
  description = <<-EOT
    VPC Flow Logs가 기록되는 CloudWatch 로그 그룹 이름.
    ⚠️ 이 값이 나온다고 로그가 배달된다는 뜻은 아니다. 로그 그룹에 실제 이벤트가 쌓이는지는
    별도로 확인한다(예: aws logs describe-log-streams로 최근 이벤트 시각 확인).
  EOT
  value       = module.vpc.flow_log_group_name
}

output "tgw_attachment_id" {
  description = <<-EOT
    이 VPC의 TGW attachment ID. hub는 이 출력을 repo 변수로 받지 않고 자기 TGW에 붙은
    attachment 전부를 data.aws_ec2_transit_gateway_vpc_attachments로 자동 발견한다. 이 출력은
    계약이 실제로 동작함을 보이는 용도로만 남긴다.
  EOT
  value       = aws_ec2_transit_gateway_vpc_attachment.spoke.id
}

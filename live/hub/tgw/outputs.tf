# live/hub/networking이 이 TGW를 data source로 조회한다(remote state 참조가 아니라 태그 기반
# 조회 — 모듈 repo 규약). 이 출력들은 다른 root가 소비하기 위한 것이 아니라, 이 root
# 단독으로도 계약이 성립함을 보이는 용도다.

output "transit_gateway_id" {
  description = "생성된 Transit Gateway ID."
  value       = aws_ec2_transit_gateway.hub.id
}

output "transit_gateway_route_table_id" {
  description = "명시적으로 소유하는 TGW 라우트테이블 ID(TGW 생성 부산물인 default RT가 아니다)."
  value       = aws_ec2_transit_gateway_route_table.hub.id
}

output "tgw_resource_share_arn" {
  description = <<-EOT
    TGW 를 spoke 에 공유하는 RAM resource share ARN. spoke 는 이 출력을 받지 않는다 —
    같은 이름(name)으로 자기 계정에서 직접 조회한다(data.aws_ram_resource_share,
    resource_owner="OTHER-ACCOUNTS").
  EOT
  value       = aws_ram_resource_share.tgw.arn
}

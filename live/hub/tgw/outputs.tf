# 다른 root는 이 출력을 소비하지 않는다. live/hub/networking은 remote state가 아니라 태그 기반
# data source로 이 TGW를 조회한다. 출력은 이 root 단독으로 계약이 성립함을 보이는 용도다.

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
    TGW를 spoke에 공유하는 RAM resource share ARN. spoke는 이 출력을 받지 않고 같은
    이름(name)으로 자기 계정에서 직접 조회한다(data.aws_ram_resource_share,
    resource_owner="OTHER-ACCOUNTS").
  EOT
  value       = aws_ram_resource_share.tgw.arn
}

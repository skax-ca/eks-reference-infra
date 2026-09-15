# live/hub/tgw: Transit Gateway 배포 루트 (허브). TGW 본체·라우트테이블·RAM 공유·prefix list.
#
# ⚠️ networking과 같은 apply에 두지 않는다. TGW가 같은 apply에서 새로 생기면 spoke attachment를
#    자동 발견하는 for_each에 TGW ID가 plan 시점 unknown으로 들어가 Invalid for_each argument로
#    실패한다(AWS provider에 복수형 TGW data source가 없어 코드로 우회할 수 없다). TGW를 이 root로
#    먼저 세워 두면 networking은 그것을 이미 존재하는 실물로 조회한다(known-at-plan).
# ⚠️ hub 자신의 attachment는 여기 없다. VPC·서브넷이 있어야 만들 수 있어 networking에 남는다.
# ⚠️ cidr_uniq는 live/hub/networking의 locals.cidr_uniq와 같아야 한다. TGW 라우트가 그 VPC의
#    secondary CIDR을 가리키는데 두 root는 state를 공유하지 않으므로 값 일치는 사람이 유지한다.
#
# 설계 근거: iac-module-library docs/architectures/gitops-hub-spoke/aws/network.md
locals {
  cidr_uniq = "10.53.0.0/16"
}

# 크로스 계정 네트워크 경로. IAM 신뢰(live/dev/eks의 cross-account-trust-role)는 "누가
# 인증되는가"만 답하고, private-only 엔드포인트의 spoke API 서버에 hub ArgoCD가 패킷을 보낼
# 경로는 이 리소스들이 만든다.
#
# ⛔ VPC Peering으로 바꾸지 않는다. 모든 VPC가 pod-dup 대역(100.64.0.0/16)을 그대로 재사용하는
#    설계라, 라우팅 대상(uniq 대역)이 안 겹쳐도 dup 대역이 겹치는 것만으로 AWS가 peering 생성을
#    "overlapping CIDR range"로 거부한다.
resource "aws_ec2_transit_gateway" "hub" {
  # AWS API가 description에 ASCII만 허용한다(그 외는 InvalidParameterValue).
  description = "hub-spoke cross-account routing for ArgoCD"

  # 둘 다 끈다. 켜면 TGW 생성의 부산물인 묵시적 기본 라우트테이블에 기대게 되는데, 그것은
  # Terraform이 생성 API를 호출하지 않아 provider default_tags가 붙지 않는다. 자동 전파는
  # attachment VPC의 전 CIDR(uniq+dup)을 그대로 전파해 peering과 같은 dup 대역 충돌을
  # 라우트테이블 안에서 재현하므로, uniq 대역만 정적 라우트(live/hub/networking)로 명시한다.
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"

  # RAM principal association이 이미 정확한 계정으로 좁혀 놓았으므로 자동 수락이 신뢰 경계를
  # 넓히지 않는다.
  auto_accept_shared_attachments = "enable"

  tags = {
    Name = "tgw-${var.workload}-${var.env}-${var.region_code}-hub"
  }
}

# provider가 직접 만드는 리소스라 default_tags가 적용된다(묵시적 기본 라우트테이블과 다른 점).
resource "aws_ec2_transit_gateway_route_table" "hub" {
  transit_gateway_id = aws_ec2_transit_gateway.hub.id

  tags = {
    Name = "tgwrt-${var.workload}-${var.env}-${var.region_code}-main"
  }
}

# RAM 공유는 spoke 계정 ID 단위로만 한다(IAM 신뢰와 같은 "정확한 대상만" 원칙).
resource "aws_ram_resource_share" "tgw" {
  name = "ram-${var.workload}-${var.env}-${var.region_code}-tgw-share"

  # true여야 한다. 초대 없는 조직 내부 공유는 조직 관리 계정에서 enable-sharing-with-aws-organization을
  # 켜야 동작하는데 배포 계정은 멤버 계정이라 그 권한이 없다(false로 apply하면 AssociateResourceShare가
  # "Principal ... is not in your AWS organization"으로 거부). 표준 계정 간 공유(초대)로 가므로
  # spoke가 초대를 수락하는 단계가 하나 생긴다(spoke 워크플로의 CI 단계가 맡는다).
  allow_external_principals = true

  tags = {
    Name = "ram-${var.workload}-${var.env}-${var.region_code}-tgw-share"
  }
}

resource "aws_ram_resource_association" "tgw" {
  resource_arn       = aws_ec2_transit_gateway.hub.arn
  resource_share_arn = aws_ram_resource_share.tgw.arn
}

resource "aws_ram_principal_association" "spoke_dev" {
  principal          = var.spoke_account_id
  resource_share_arn = aws_ram_resource_share.tgw.arn
}

# 허브 uniq CIDR을 RAM으로 공유해, spoke가 라우트·SG 규칙에 "10.53.0.0/16"을 하드코딩하지 않게
# 한다. 태그는 계정 경계를 못 넘지만 RAM이 공유하는 리소스 자체(resource_arns)는 넘고, 공유된
# 관리형 접두사 목록은 참가자 계정이 SG 규칙·라우트에서 직접 참조할 수 있다.
resource "aws_ec2_managed_prefix_list" "hub_uniq" {
  name           = "pl-${var.workload}-${var.env}-${var.region_code}-uniq"
  address_family = "IPv4"
  max_entries    = 1 # 허브 uniq CIDR 하나. max_entries는 mutable(교체 아님)이라 필요하면 늘린다.

  entry {
    cidr        = local.cidr_uniq
    description = "hub uniq CIDR"
  }

  tags = {
    Name = "pl-${var.workload}-${var.env}-${var.region_code}-uniq"
  }
}

resource "aws_ram_resource_association" "prefix_list" {
  resource_arn       = aws_ec2_managed_prefix_list.hub_uniq.arn
  resource_share_arn = aws_ram_resource_share.tgw.arn
}

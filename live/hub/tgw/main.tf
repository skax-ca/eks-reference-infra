# live/hub/tgw — Transit Gateway 배포 루트 (허브)
#
# ⚠️ **왜 live/hub/networking에서 분리했나**(2026-08-24). TGW가 hub networking과 같은
# apply에서 새로 생기면, 그 TGW에 붙은 spoke attachment를 자동 발견하는 for_each가
# "TGW ID가 plan 시점에 unknown"이라 Invalid for_each argument로 실패한다(hub를 완전히
# destroy한 뒤 처음부터 재배포할 때 실제로 재현됨 — AWS provider에 복수형 TGW data source가
# 없고 단수형은 매칭 0건에서 하드 에러라 순수 코드 우회가 불가능함을 확인했다). TGW를 먼저
# 이 root로 세워두면, hub networking은 그 TGW를 "이미 존재하는 실물"로 data source
# 조회(known-at-plan)할 수 있다 — CLAUDE.md 8-4(레이어로 키운다)와 같은 원리다.
#
# ⚠️ **hub 자신의 attachment는 여기 없다** — `aws_ec2_transit_gateway_vpc_attachment.hub`는
# VPC(`module.vpc.vpc_id`·서브넷)가 있어야 만들 수 있어 VPC보다 먼저 존재할 수 없다(순환
# 의존). 그 리소스는 그대로 live/hub/networking에 남는다.
#
# ⚠️ **이 CIDR 값은 live/hub/networking의 locals.cidr_uniq와 반드시 같아야 한다** — TGW
# 라우트가 실제로 그 VPC의 secondary CIDR을 가리키기 때문이다. 두 root가 state를 공유하지
# 않으므로 값 일치는 사람이 유지한다(네이밍 규약과 같은 종류의 결합).
locals {
  cidr_uniq = "10.53.0.0/16"
}

# ── 크로스 계정 네트워크 경로 — Transit Gateway (모듈 repo docs/02-choose-your-path.md
#    「네트워크 경로」 절, 2026-08-19) ───────────────────────────────────────────────
#
# IAM 신뢰(live/dev/eks 의 cross-account-trust-role)는 "누가 인증되는가"만 답한다.
# private-only 엔드포인트에서 허브 ArgoCD 가 spoke API 서버에 패킷을 보낼 경로 자체가
# 없으면 인증이 성립해도 도달하지 못한다 — 이 리소스들이 그 경로다.
#
# ⛔ **VPC Peering 이 아니다.** 처음엔 Peering 을 시도했으나 AWS 가
#    "Failed due to ... overlapping CIDR range" 로 즉시 거부했다(2026-08-19 실측) — 이
#    VPC 의 pod-dup 대역(100.64.0.0/16)을 모든 스포크가 그대로 재사용하는 설계라, 실제
#    라우팅 대상(uniq 대역)이 안 겹쳐도 dup 대역이 겹치는 것만으로 peering 자체가 거부된다.
#    자세한 근거는 모듈 repo 문서 참조.
resource "aws_ec2_transit_gateway" "hub" {
  # description 은 AWS API 가 ASCII 만 허용한다(2026-08-20 실측: InvalidParameterValue).
  description = "hub-spoke cross-account routing for ArgoCD"

  # 연결·전파 둘 다 끈다 — AWS 가 TGW 생성의 부산물로 만드는 "기본" 라우트테이블에
  # 기대지 않고, 아래 aws_ec2_transit_gateway_route_table 을 직접 만들어 쓰기 위해서다.
  # 그 묵시적 기본 라우트테이블은 Terraform 이 생성 API 를 호출하지 않아 provider 의
  # default_tags 가 안 붙는다(2026-08-20 실측: 무태그 확인) — 명시적으로 만든 라우트테이블은
  # provider 가 직접 만드는 리소스라 태그가 그대로 적용된다(모듈 repo
  # docs/06-conventions.md 「2」 강제 방식 6번). 자동 전파는 애초에 attachment 의 VPC 전
  # CIDR(uniq+dup)을 그대로 전파해 peering 과 같은 dup 대역 충돌을 재현하므로 끈다 —
  # uniq 대역만 정적 라우트(live/hub/networking)로 명시한다.
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"

  # RAM 공유로 들어오는 attachment 를 자동 수락한다 — RAM principal association 이 이미
  # 정확한 계정으로 좁혀 놓았으므로(아래) 자동 수락이 신뢰 경계를 넓히지 않는다.
  auto_accept_shared_attachments = "enable"

  tags = {
    Name = "tgw-${var.workload}-${var.env}-${var.region_code}-hub"
  }
}

# 명시적으로 소유하는 라우트테이블 — TGW 생성의 부산물(default_route_table_association 로
# 자동 연결되는 것)이 아니라 이 resource 블록이 직접 만든다. provider 가 직접 만드는
# 리소스라 default_tags 가 그대로 적용된다(위 주석 참조).
resource "aws_ec2_transit_gateway_route_table" "hub" {
  transit_gateway_id = aws_ec2_transit_gateway.hub.id

  tags = {
    Name = "tgwrt-${var.workload}-${var.env}-${var.region_code}-main"
  }
}

# ── RAM 공유 — spoke 계정만 정확히 지정한다(IAM 신뢰와 같은 "정확한 대상만" 원칙) ──────
resource "aws_ram_resource_share" "tgw" {
  name = "ram-${var.workload}-${var.env}-${var.region_code}-tgw-share"

  # true — hub·spoke(asset) 둘 다 조직(o-rs1oivwow6) 소속이지만, 초대 없는 조직 내부 공유는
  # 조직 관리 계정(694171854892, 우리는 멤버 계정)에서 enable-sharing-with-aws-organization을
  # 먼저 실행해야 켜진다(2026-08-20 실측: 그 상태로 apply 시 RAM AssociateResourceShare가
  # "Principal ... is not in your AWS organization"으로 거부). 관리 계정 권한이 없으므로
  # 표준 계정 간 공유(초대)로 간다 — spoke가 aws_ram_resource_share_accepter로 수락해야 한다.
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

# ── 관리형 접두사 목록 — 허브의 uniq CIDR을 RAM으로 공유 ────────────────────────
#
# 스포크(dev)가 허브로 가는 라우트·SG 규칙에서 "10.53.0.0/16" 을 CIDR 텍스트로 하드코딩하지
# 않게 한다. TGW ID 를 발견하는 것과 같은 원칙("이름이 아니라 RAM resource_arns 로 발견")을
# CIDR 에도 적용한다 — 태그로는 계정 경계를 못 넘지만(2026-08-20 실측), RAM 이 공유하는
# 리소스 자체(resource_arns)는 넘는다. 프리픽스 리스트는 그 성질을 갖는 리소스다(AWS 공식:
# RAM 으로 공유된 관리형 접두사 목록은 참가자 계정이 SG 규칙·라우트에서 직접 참조할 수 있다).
resource "aws_ec2_managed_prefix_list" "hub_uniq" {
  name           = "pl-${var.workload}-${var.env}-${var.region_code}-uniq"
  address_family = "IPv4"
  max_entries    = 1 # 허브 자신의 uniq CIDR 하나만 담는다. max_entries 는 mutable(교체 아님) — 필요해지면 늘린다.

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

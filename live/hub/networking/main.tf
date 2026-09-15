# live/hub/networking: VPC 배포 루트 (허브). VPC·서브넷·hub 자신의 TGW attachment·hub 측 라우트.
#
# iac-module-library examples/vpc-enterprise를 착수 템플릿으로 복사해 이 계정의 대역에 맞췄다.
# ⚠️ enterprise 구성은 secondary CIDR 2개와 isolated 라우팅이 실제로 만들어지므로, apply 성공이
#    "그 CIDR·라우팅이 의도대로 동작한다"까지 보장하지 않는다. 검증은 별도로 한다.
#
# 설계 근거: iac-module-library docs/architectures/gitops-hub-spoke/aws/network.md

locals {
  # CIDR 3계층. primary는 인프라 전용 소형으로 최소화하고 워크로드는 secondary에 둔다.
  #
  # ⚠️ 예제 값을 그대로 쓰지 않았다. 대상이 공용 개발 계정이라 실제 대역을 조회해 비어 있는 것을
  #    골랐다. 겹침이 지금 장애를 만들지는 않지만 이 repo는 고객사에 복사해 줄 형태라, 겹치는
  #    대역을 예시로 남기면 그대로 복사돼 나간다.
  cidr_primary = "10.52.0.0/24"  # uniq 소형, ep·tgw 전용
  cidr_uniq    = "10.53.0.0/16"  # uniq, 라우팅 가능(온프레미스 도달 가정)
  cidr_dup     = "100.64.0.0/16" # dup 허용, 비라우팅(RFC 6598)

  # cidrsubnet() 파생. 계산의 소유는 모듈이 아니라 소비자 루트다(고객사는 이 locals를 복사해
  # 자기 대역으로 고친다). 겹침은 AWS API가 apply 시에만 거부하므로 배치를 표로 남긴다:
  #
  #   vm-uniq    /20 × 2  10.53.0.0/20      10.53.16.0/20
  #   pub-uniq   /24 × 2  10.53.32.0/24     10.53.33.0/24    ┐
  #   elb-uniq   /24 × 2  10.53.34.0/24     10.53.35.0/24    │ 모두 10.53.32.0/20 안에서
  #   node-uniq  /24 × 2  10.53.36.0/24     10.53.37.0/24    │ 파생, 겹치지 않는다
  #   data-uniq  /24 × 3  10.53.38.0/24 …   10.53.40.0/24    │
  #   db-uniq    /26 × 2  10.53.41.0/26     10.53.41.64/26   ┘ (/24 하나를 다시 /26으로)
  #   pod-dup    /18 × 2  100.64.0.0/18     100.64.64.0/18
  #   ep-uniq    /27 × 2  10.52.0.0/27      10.52.0.32/27    ┐ primary /24 안에서
  #   tgw-uniq   /28 × 3  10.52.0.192/28 …  10.52.0.224/28   ┘ 앞/뒤로 떨어뜨려 배치

  # ⚠️ live/hub/eks가 모듈에 넘기는 purpose="main"·serial="01" 조합과 정확히 같아야 한다.
  #    VPC는 이 이름으로 서브넷 디스커버리 태그를, EKS 모듈은 같은 이름으로 node SG 태그를
  #    붙인다. 어긋나면 ELB·Karpenter selector가 빈 결과를 내고 프로비저닝이 에러 없이 실패한다.
  #    두 루트는 state를 공유하지 않으므로 이 일치는 네이밍 규약으로 유지한다.
  eks_cluster_name = "eks-${var.workload}-${var.env}-${var.region_code}-main-01"

  uniq_small_block = cidrsubnet(local.cidr_uniq, 4, 2)

  vm_cidrs   = [for i in [0, 1] : cidrsubnet(local.cidr_uniq, 4, i)]
  pub_cidrs  = [for i in [0, 1] : cidrsubnet(local.uniq_small_block, 4, i)]
  elb_cidrs  = [for i in [2, 3] : cidrsubnet(local.uniq_small_block, 4, i)]
  node_cidrs = [for i in [4, 5] : cidrsubnet(local.uniq_small_block, 4, i)]
  data_cidrs = [for i in [6, 7, 8] : cidrsubnet(local.uniq_small_block, 4, i)]
  db_cidrs   = [for i in [0, 1] : cidrsubnet(cidrsubnet(local.uniq_small_block, 4, 9), 2, i)]
  pod_cidrs  = [for i in [0, 1] : cidrsubnet(local.cidr_dup, 2, i)]
  ep_cidrs   = [for i in [0, 1] : cidrsubnet(local.cidr_primary, 3, i)]
  tgw_cidrs  = [for i in [12, 13, 14] : cidrsubnet(local.cidr_primary, 4, i)]
}

module "vpc" {
  # ⛔ 소싱 URL은 git::https:// 하나로 유지한다. 인증은 CI에서만 insteadOf로 주입되고 이 코드는
  #    인증 방식을 모른다. SSH URL로 바꾸면 로컬/CI 갈래가 생긴다.
  # ⛔ ?ref=는 정확 태그 핀이다. git 소싱에 ~>는 동작하지 않는다. 업그레이드는 이 줄을 올리는
  #    명시적 커밋이고 그 커밋이 곧 승격 게이트다.
  source = "git::https://github.com/skax-ca/iac-module-library.git//modules/aws/vpc?ref=vpc-v0.4.0&depth=1"

  # 리소스 타입 약어는 모듈이 조합한다. {demo, hub, an2} → vpc-demo-hub-an2-main
  naming = {
    workload    = var.workload
    env         = var.env
    region_code = var.region_code
  }
  purpose = "main"

  cidr_block            = local.cidr_primary
  secondary_cidr_blocks = [local.cidr_uniq, local.cidr_dup]

  # 기본 AZ는 a·c, 3AZ 그룹만 b를 추가로 쓴다(서울 리전 관례). 2AZ 그룹이 모두 a·c에 몰리는
  # 것은 의도된 결과다.
  az_count     = 3
  az_selection = ["a", "c", "b"]

  subnet_groups = {
    # 인터넷 대면 LB + NAT 호스팅. ALB 최소 2AZ 충족.
    "pub-uniq" = {
      type     = "public"
      cidrs    = local.pub_cidrs
      eks_role = "elb"
    }

    # 온프레미스 연동 방화벽 오픈 단위. 내부 LB ENI는 아웃바운드 개시가 없어 isolated로 둔다.
    # 온프레미스 왕복 경로는 TGW 운영 라우트가 추가될 때 생긴다.
    "elb-uniq" = {
      type     = "isolated"
      cidrs    = local.elb_cidrs
      eks_role = "internal-elb"
    }

    # VM 워크로드. NAT 아웃바운드.
    "vm-uniq" = {
      type  = "private"
      cidrs = local.vm_cidrs
    }

    # EKS 노드(custom networking). node-SNAT의 소스이자 방화벽 오픈 단위.
    "node-uniq" = {
      type  = "private"
      cidrs = local.node_cidrs

      # Karpenter discovery의 subnet 절반. SG 절반은 EKS 모듈(live/hub/eks)이 붙인다.
      # ⚠️ 한쪽만 붙으면 subnetSelectorTerms가 빈 결과를 내고 프로비저닝이 조용히 실패한다.
      #    값은 SG 쪽과 같은 local.eks_cluster_name이어야 한다.
      extra_tags = {
        "karpenter.sh/discovery" = local.eks_cluster_name
      }
    }

    # EKS Pod 전용(ENIConfig). Pod의 VPC 외부 egress는 노드 primary ENI로 SNAT되어 노드 그룹
    # RT를 타므로 Pod 서브넷엔 기본 경로가 불필요하다 → isolated.
    "pod-dup" = {
      type  = "isolated"
      cidrs = local.pod_cidrs
    }

    # RDS 등 관계형(Multi-AZ = 2). 소수 고정 ENI라 소형 CIDR.
    "db-uniq" = {
      type  = "isolated"
      cidrs = local.db_cidrs
    }

    # MSK·OpenSearch·Redis. 3AZ 공식 권장(quorum). db와 분리하는 이유는 AZ 수 요구와 IP 소모
    # 프로파일이 다르기 때문이다. 라우팅은 db와 같으므로 분리 근거가 아니다.
    "data-uniq" = {
      type  = "isolated"
      cidrs = local.data_cidrs
    }

    # VPC interface endpoint ENI 전용. b존 호출은 cross-AZ 폴백.
    "ep-uniq" = {
      type  = "isolated"
      cidrs = local.ep_cidrs
    }

    # TGW attachment 전용(/28 권장).
    # ⚠️ 워크로드가 존재하는 모든 AZ를 커버해야 한다. attachment 없는 AZ의 리소스는 TGW에
    #    도달하지 못한다.
    "tgw-uniq" = {
      type  = "isolated"
      cidrs = local.tgw_cidrs
    }
  }

  # eks_role이 지정된 그룹(pub-uniq·elb-uniq)에만 cluster 태그가 함께 붙는다. 클러스터가 아직
  # 없어도 태그가 먼저 붙는 것은 의도된 순서다(서브넷 디스커버리 태그는 클러스터 생성 시점에
  # 이미 있어야 한다).
  # ⚠️ serial을 빠뜨려 "-main"으로 두면 실제 클러스터명 "-main-01"과 어긋난다.
  eks_cluster_name = local.eks_cluster_name

  # 비용 우선으로 NAT 1개를 전 AZ가 공유한다. false(AZ별 NAT)로 가용성을 택할 때는 pub 그룹의
  # AZ 수가 private 그룹 최대 AZ 수 이상이어야 한다(모듈의 precondition).
  single_nat_gateway = true

  # 공용 개발 계정에서 실수 삭제의 마지막 방어선이다.
  # ⚠️ 켜면 teardown이 2단계가 된다(false로 apply → destroy 워크플로). 절차는 docs/hub-lifecycle.md.
  # ⛔ false로 바꾼 커밋을 main에 남겨두지 않는다. 지금 false인 것은 철거·재구축 중이라서다.
  #    재구축이 끝나면 true로 되돌린다.
  deletion_protection = false
}

# 크로스 계정 네트워크 경로. IAM 신뢰(live/dev/eks의 cross-account-trust-role)는 "누가
# 인증되는가"만 답하고, private-only 엔드포인트의 spoke API 서버에 hub ArgoCD가 패킷을 보낼
# 경로는 이 리소스들이 만든다.
#
# ⛔ VPC Peering으로 바꾸지 않는다. 모든 VPC가 pod-dup 대역(100.64.0.0/16)을 그대로 재사용하는
#    설계라, 라우팅 대상(uniq 대역)이 안 겹쳐도 dup 대역이 겹치는 것만으로 AWS가 peering 생성을
#    "overlapping CIDR range"로 거부한다.
#
# TGW 자체는 live/hub/tgw 소관이고 배포 순서도 그쪽이 먼저다. 같은 apply에서 새로 생기면
# 아래 spoke 자동 발견 for_each에 TGW ID가 plan 시점 unknown으로 들어가 Invalid for_each
# argument로 실패한다.
#
# ⚠️ state 필터가 필수다. AWS는 destroy된 TGW도 한동안 State=deleted로 DescribeTransitGateways에
#    계속 반환하므로 tag:Name만으로는 유령 항목이 매칭되고, 그 유령의 route table은 없어 아래
#    aws_ec2_transit_gateway_route_table 조회가 "no matching"으로 실패한다.
data "aws_ec2_transit_gateway" "hub" {
  filter {
    name   = "tag:Name"
    values = ["tgw-${var.workload}-${var.env}-${var.region_code}-hub"]
  }
  filter {
    name   = "state"
    values = ["available"]
  }
}

# transit-gateway-id 필터만으로 유일하게 좁혀진다. live/hub/tgw의 TGW는 default_route_table_association/
# propagation = "disable"이라 자동 생성 default RT가 없고 명시로 만든 라우트테이블 하나만 있다.
data "aws_ec2_transit_gateway_route_table" "hub" {
  filter {
    name   = "transit-gateway-id"
    values = [data.aws_ec2_transit_gateway.hub.id]
  }
}

data "aws_caller_identity" "current" {}

# 허브 자신의 attachment. ArgoCD(argocd-application-controller)가 도는 서브넷에 붙는다.
# VPC(위 module.vpc)가 있어야 만들 수 있어 live/hub/tgw로 옮길 수 없다(순환 의존).
resource "aws_ec2_transit_gateway_vpc_attachment" "hub" {
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.subnet_ids_by_group["node-uniq"]
  transit_gateway_id = data.aws_ec2_transit_gateway.hub.id

  tags = {
    Name = "tgwa-${var.workload}-${var.env}-${var.region_code}-main"
  }
}

# hub(TGW owner)가 명시적 연결 리소스로 양쪽 attachment를 우리 RT로 끌어온다.
#
# ⛔ attachment 리소스의 transit_gateway_default_route_table_association = false로 대신하지
#    않는다. hub attachment에 그 인자를 주면 "Modifications complete" 뒤에도 옛 RT 연결이 그대로
#    남아 AssociateTransitGatewayRouteTable이 Resource.AlreadyAssociated로 실패한다. AWS 공식
#    문서도 두 리소스로 같은 연결을 관리하지 말라고 경고한다. spoke attachment는 RAM으로 받은
#    쪽이라 그 인자 자체를 못 쓴다("cannot be configured ... with Resource Access Manager shared
#    EC2 Transit Gateways").
resource "aws_ec2_transit_gateway_route_table_association" "hub" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.hub.id
  transit_gateway_route_table_id = data.aws_ec2_transit_gateway_route_table.hub.id
  replace_existing_association   = true
}

# spoke 자동 발견: 이 TGW에 RAM으로 붙은 attachment 전부. 복수형 데이터소스는 "없으면 빈
# 리스트"라(단수형과 달리 에러가 아니다) spoke가 하나도 없어도, 여러 개여도 이 apply는 성공한다.
# 다음 spoke를 추가할 때 이 파일을 고치지 않아도 되는 것이 목적이다.
data "aws_ec2_transit_gateway_vpc_attachments" "spokes" {
  filter {
    name   = "transit-gateway-id"
    values = [data.aws_ec2_transit_gateway.hub.id]
  }
  filter {
    name   = "state"
    values = ["available"]
  }
}

# ⚠️ 허브 자신의 attachment도 포함된 채로 발견된다("spoke"가 아니라 "discovered"인 이유).
#    attachment ID로 허브 것을 미리 제외하지 않는다. 그 ID는 이 apply에서 새로 생기는 값이라
#    plan 시점 unknown이고, for_each 조건에 섞으면 TGW를 별도 root로 분리해 없앤 바로 그
#    실패가 재현된다. 아래 local.spoke_attachments에서 vpc_owner_id(항상 known-at-plan)로
#    걸러낸다.
data "aws_ec2_transit_gateway_vpc_attachment" "discovered" {
  for_each = toset(data.aws_ec2_transit_gateway_vpc_attachments.spokes.ids)

  id = each.value
}

locals {
  spoke_attachments = {
    for k, v in data.aws_ec2_transit_gateway_vpc_attachment.discovered : k => v
    if v.vpc_owner_id != data.aws_caller_identity.current.account_id
  }
}

resource "aws_ec2_transit_gateway_route_table_association" "spoke" {
  for_each = local.spoke_attachments

  transit_gateway_attachment_id  = each.value.id
  transit_gateway_route_table_id = data.aws_ec2_transit_gateway_route_table.hub.id
  # 이미 우리 RT에 연결된 spoke에는 no-op이라 신규 spoke에도 그대로 안전하다.
  replace_existing_association = true
}

# ⚠️ CIDR은 태그에서 읽지 않는다. EC2·RAM 태그는 종류를 가리지 않고 계정 경계를 못 넘는다
#    (describe-tags·DescribeTransitGatewayVpcAttachments·aws_ram_resource_share의 tags 전부
#    cross-account 조회 시 빈 값). 대신 attachment의 vpc_owner_id(태그가 아니라 EC2 API 고유
#    속성이라 cross-account로도 보인다)로 spoke를 식별해 이 지도에서 CIDR을 찾는다. hub는
#    RAM 초대를 보내려면 이미 spoke 계정 ID를 알아야 하므로(live/hub/tgw의
#    aws_ram_principal_association), 같은 자리에 CIDR 하나만 더 적는 것은 새 수동 단계가
#    아니라 기존 단계의 확장이다.
locals {
  spoke_uniq_cidrs = {
    (var.spoke_account_id) = "10.51.0.0/16" # dev(asset 계정), live/dev/networking의 cidr_uniq
  }
}

# 허브 VPC 라우트테이블(node-uniq·vm-uniq, 둘 다 실제 hub→spoke 트래픽 발생원이다: node는
# ArgoCD 파드가 SNAT되어 나가는 소스, vm-uniq는 workbench 자신의 소스)에서 발견된 spoke마다
# 라우트를 하나씩 얹는다. route_table_ids_by_group[...]는 AZ별 RT 리스트라 (RT × spoke)
# 곱집합이 된다.
#
# ⚠️ key는 attachment ID도 라우트테이블 ID도 아니라 그룹명+인덱스+spoke_account_id로 고정한다.
#    attachment ID를 key에 섞으면 destroy→재배포마다 불필요한 교체가 생긴다. 라우트테이블 ID를
#    key 조합(toset(concat(...)))에 쓰는 것도 같은 문제다: hub VPC를 처음부터 새로 만드는
#    apply에서는 그 ID들이 plan 시점에 전부 unknown이고, toset()은 unknown 원소가 하나라도
#    있으면 결과 집합 전체를 "known after apply"로 만들어 for_each key까지 전염시켜 Invalid
#    for_each argument가 된다. 그룹명·인덱스(range)·spoke_account_id는 config 값만으로 plan
#    시점에 확정되므로 이 셋을 key로 쓰고, 실제 라우트테이블 ID는 리소스 인자(route_table_id)
#    자리에서만 참조한다(인자 값은 unknown이어도 되고 key만 known이면 된다).
locals {
  hub_rt_indices = merge([
    for group_name in ["node-uniq", "vm-uniq"] : {
      for idx in range(length(module.vpc.route_table_ids_by_group[group_name])) :
      "${group_name}.${idx}" => { group = group_name, idx = idx }
    }
  ]...)

  spoke_account_ids_attached = [for account_id, cidr in local.spoke_uniq_cidrs : account_id
    if contains(
      [for a in local.spoke_attachments : a.vpc_owner_id],
      account_id,
  )]

  hub_rt_x_spoke = merge([
    for rt_key, rt in local.hub_rt_indices : {
      for account_id in local.spoke_account_ids_attached :
      "${rt_key}.${account_id}" => merge(rt, { account_id = account_id })
    }
  ]...)
}

resource "aws_route" "vpc_to_spoke" {
  for_each = local.hub_rt_x_spoke

  route_table_id         = module.vpc.route_table_ids_by_group[each.value.group][each.value.idx]
  destination_cidr_block = local.spoke_uniq_cidrs[each.value.account_id]
  transit_gateway_id     = data.aws_ec2_transit_gateway.hub.id

  # aws_route의 delete 기본 타임아웃은 5m. 위 key 안정화로 replace는 거의 없지만 예외를 위한
  # 안전망이다.
  timeouts {
    delete = "15m"
  }

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.hub]
}

# TGW 라우트테이블은 hub가 소유한다(TGW owner만 자기 라우트테이블에 라우트를 넣을 수 있다는
# AWS 제약). 자동 전파를 껐으므로 두 방향 모두 정적 라우트로 명시한다.
#
# hub CIDR → hub 자신의 attachment. spoke → hub 방향이 이 라우트로 뚫린다.
resource "aws_ec2_transit_gateway_route" "hub_via_hub_attachment" {
  destination_cidr_block         = local.cidr_uniq
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.hub.id
  transit_gateway_route_table_id = data.aws_ec2_transit_gateway_route_table.hub.id

  depends_on = [aws_ec2_transit_gateway_route_table_association.hub]
}

# 발견된 spoke마다 TGW 라우트테이블에 라우트를 하나씩 얹는다. 대상 CIDR은 local.spoke_uniq_cidrs에서
# vpc_owner_id로 찾는다. spoke가 늘어도 지도에 계정 ID·CIDR 한 줄만 추가하면 된다.
resource "aws_ec2_transit_gateway_route" "tgw_rt_to_spoke" {
  for_each = local.spoke_attachments

  destination_cidr_block         = local.spoke_uniq_cidrs[each.value.vpc_owner_id]
  transit_gateway_attachment_id  = each.value.id
  transit_gateway_route_table_id = data.aws_ec2_transit_gateway_route_table.hub.id

  depends_on = [aws_ec2_transit_gateway_route_table_association.spoke]
}

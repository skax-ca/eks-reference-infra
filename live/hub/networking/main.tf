# live/hub/networking — VPC 배포 루트 (허브)
#
# 모듈 repo examples/vpc-enterprise 를 **착수 템플릿으로 복사**해 이 계정의 대역에 맞춘 것이다.
# 그 예제의 목적은 검증이 아니라 착수 템플릿이고(examples/vpc-enterprise/README.md), 이 파일이
# 그 용법의 첫 실제 인스턴스다.
#
# ⚠️ minimal(examples/vpc) 이 아니라 enterprise 를 택한 결과로 **첫 apply 의 판정 범위가 넓어진다**
#    — secondary CIDR 2개와 isolated 라우팅이 실제로 만들어지기 때문이다.
#    무엇이 판정되고 무엇이 안 되는지는 `docs/deployment-facts.md`가 표로 관리한다.
#    표에 없는 것을 "검증했다"고 쓰지 않는다(`CLAUDE.md` 참조).

locals {
  # ── CIDR 3계층 (모듈 repo 규약) ─────────────────────────────────────────────
  #
  # primary 는 인프라 전용 소형으로 최소화하고 워크로드는 secondary 에 배치한다.
  #
  # ⚠️ 이 값들은 예제에서 **그대로 가져오지 않았다.** 대상 계정이 공용 개발 계정이라
  #    실제 대역을 재조회해 비어 있는 것을 골랐다(hub 신설 시점의 VPC CIDR 전수 조회 결과다.
  #    live/dev 가 쓰던 10.50/24·10.51/16 은 VPC 자체가 이미 파기됐지만, 코드는 남아 있어
  #    재사용하지 않고 새 대역을 골랐다):
  #      사용 중 · 10.0/16(×6)  10.1/16  10.10/16  10.10/21  10.20/16  10.38/16  10.90/16
  #                10.100/16  10.200/20  10.236.56/23  20.0/16(×2)  100.0/16  100.100/16
  #                110.0/26  172.16/20  172.30/16  172.31/16  192.168/16  210.0/16
  #      우리 것 · 10.52.0.0/24 · 10.53.0.0/16 · 100.64.0.0/16  → 어느 것과도 겹치지 않는다
  #
  #    겹침 자체가 지금 장애를 만들지는 않는다(peering·TGW 가 없다). 그러나 이 repo 는
  #    **고객사에 복사해 줄 형태**라, 겹치는 대역을 예시로 남기면 그대로 복사돼 나간다.
  cidr_primary = "10.52.0.0/24"  # uniq 소형 — ep·tgw 전용
  cidr_uniq    = "10.53.0.0/16"  # uniq — 라우팅 가능(온프레미스 도달 가정)
  cidr_dup     = "100.64.0.0/16" # dup 허용 — 비라우팅(RFC 6598)

  # ── cidrsubnet() 파생 ───────────────────────────────────────────────────────
  # 계산의 소유가 **모듈이 아니라 소비자 루트**다. 고객사는 이 locals 를 복사해 자기 대역으로 고친다.
  #
  # 겹침은 AWS API 가 apply 시 거부하므로(plan 으로는 안 잡힌다) 배치를 표로 남긴다:
  #
  #   vm-uniq    /20 × 2  10.53.0.0/20      10.53.16.0/20
  #   pub-uniq   /24 × 2  10.53.32.0/24     10.53.33.0/24    ┐
  #   elb-uniq   /24 × 2  10.53.34.0/24     10.53.35.0/24    │ 모두 10.53.32.0/20 안에서
  #   node-uniq  /24 × 2  10.53.36.0/24     10.53.37.0/24    │ 파생 — 겹치지 않는다
  #   data-uniq  /24 × 3  10.53.38.0/24 …   10.53.40.0/24    │
  #   db-uniq    /26 × 2  10.53.41.0/26     10.53.41.64/26   ┘ (/24 하나를 다시 /26 으로)
  #   pod-dup    /18 × 2  100.64.0.0/18     100.64.64.0/18
  #   ep-uniq    /27 × 2  10.52.0.0/27      10.52.0.32/27    ┐ primary /24 안에서
  #   tgw-uniq   /28 × 3  10.52.0.192/28 …  10.52.0.224/28   ┘ 앞/뒤로 떨어뜨려 배치
  # ── EKS 클러스터 이름 (live/hub/eks 루트와 공유하는 결정적 상수) ────────────
  # 🔑 이 문자열은 live/hub/eks 루트가 모듈에 넘기는 purpose="main"·serial="01" 조합과
  #    **정확히 같아야 한다** → eks-<workload>-<env>-<region>-main-01.
  #    VPC 는 이 이름으로 서브넷 디스커버리 태그를 붙이고 EKS 모듈은 같은 이름으로 node SG 태그를
  #    붙인다. 어긋나면 ELB·Karpenter selector 가 빈 결과를 내고 프로비저닝이 에러 없이 실패한다.
  #    ⚠️ 이름은 state 를 공유하지 않는 두 루트가 각자 조합한다 — 결합이 아니라 네이밍 규약이다.
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
  # ⛔ 소싱 URL 은 git::https:// **하나로 유지한다.** 인증은 CI 에서만 insteadOf 로 주입되고
  #    이 코드는 인증 방식을 모른다. SSH URL 로 바꾸면 로컬/CI 갈래가 생긴다.
  # ⛔ ?ref= 는 **정확 태그 핀**이다. git 소싱에 ~> 는 동작하지 않는다 —
  #    업그레이드는 이 줄을 올리는 명시적 커밋이고, 그 커밋이 곧 승격 게이트다.
  source = "git::https://github.com/skax-ca/iac-module-library.git//modules/vpc?ref=vpc-v0.3.0&depth=1"

  # 소비자는 리소스 타입 약어를 타이핑하지 않는다 — 모듈이 조합한다(모듈 repo 규약).
  # {demo, hub, an2} → vpc-demo-hub-an2-main · snet-demo-hub-an2-pub-uniq-a
  naming = {
    workload    = var.workload
    env         = var.env
    region_code = var.region_code
  }
  purpose = "main"

  cidr_block            = local.cidr_primary
  secondary_cidr_blocks = [local.cidr_uniq, local.cidr_dup]

  # 기본 AZ 는 a·c 로 두고 3AZ 그룹만 b 를 추가로 쓴다(서울 리전 관례).
  # 2AZ 그룹이 모두 a·c 에 몰리는 것은 의도된 결과다.
  az_count     = 3
  az_selection = ["a", "c", "b"]

  subnet_groups = {
    # 인터넷 대면 LB + NAT 호스팅. ALB 최소 2AZ 충족.
    "pub-uniq" = {
      type     = "public"
      cidrs    = local.pub_cidrs
      eks_role = "elb"
    }

    # 온프레미스 연동 방화벽 오픈 단위. 내부 LB ENI 는 아웃바운드 개시가 없어 isolated 로 둔다 —
    # 온프레미스 왕복 경로는 TGW 운영 라우트가 추가될 때 생긴다(의도된 순서).
    "elb-uniq" = {
      type     = "isolated"
      cidrs    = local.elb_cidrs
      eks_role = "internal-elb"
    }

    # VM 워크로드 — NAT 아웃바운드.
    "vm-uniq" = {
      type  = "private"
      cidrs = local.vm_cidrs
    }

    # EKS 노드(custom networking) — node-SNAT 의 소스이자 방화벽 오픈 단위.
    "node-uniq" = {
      type  = "private"
      cidrs = local.node_cidrs

      # Karpenter discovery 의 **subnet 절반**. SG 절반은 EKS 모듈(live/hub/eks)이 붙인다.
      #    ⚠️ 한쪽만 붙으면 subnetSelectorTerms 가 빈 결과를 내고 프로비저닝이 조용히 실패한다
      #       (모듈 주석의 "PoC 실제 사고"). 값은 위 local.eks_cluster_name — SG 쪽과 같아야 한다.
      extra_tags = {
        "karpenter.sh/discovery" = local.eks_cluster_name
      }
    }

    # EKS Pod 전용(ENIConfig). Pod 의 VPC 외부 egress 는 노드 primary ENI 로 SNAT 되어
    # 노드 그룹 RT 를 타므로 Pod 서브넷엔 기본 경로가 불필요하다 → isolated.
    "pod-dup" = {
      type  = "isolated"
      cidrs = local.pod_cidrs
    }

    # RDS 등 관계형(Multi-AZ = 2). 소수 고정 ENI 라 소형 CIDR.
    "db-uniq" = {
      type  = "isolated"
      cidrs = local.db_cidrs
    }

    # MSK·OpenSearch·Redis — 3AZ 공식 권장(quorum). db 와 분리하는 이유는 AZ 수 요구와
    # IP 소모 프로파일이 다르기 때문이다. 라우팅은 db 와 같으므로 분리 근거가 아니다.
    "data-uniq" = {
      type  = "isolated"
      cidrs = local.data_cidrs
    }

    # VPC interface endpoint ENI 전용. b존 호출은 cross-AZ 폴백.
    "ep-uniq" = {
      type  = "isolated"
      cidrs = local.ep_cidrs
    }

    # TGW attachment 전용(/28 권장). ⚠️ 워크로드가 존재하는 모든 AZ 를 커버해야 한다 —
    # attachment 없는 AZ 의 리소스는 TGW 에 도달하지 못한다(AWS 공식 권고).
    "tgw-uniq" = {
      type  = "isolated"
      cidrs = local.tgw_cidrs
    }
  }

  # eks_role 이 지정된 그룹(pub-uniq · elb-uniq)에만 cluster 태그가 함께 붙는다.
  # ⚠️ 이 이름의 EKS 클러스터는 아직 없다(live/hub/eks 가 apply 되면 생긴다). 태그가 먼저 붙는 것은
  #    무해하고 의도된 순서다 — 서브넷 디스커버리 태그는 클러스터 생성 시점에 이미 있어야 한다.
  # 🔑 값은 local.eks_cluster_name 하나로 통일한다(node-uniq karpenter 태그와 같은 출처) —
  #    serial 을 빠뜨려 "-main" 으로 두면 실제 클러스터명 "-main-01" 과 어긋난다.
  eks_cluster_name = local.eks_cluster_name

  # dev 는 비용 우선 — NAT 1개를 전 AZ 가 공유한다. prd 는 false(AZ별 NAT)로 가용성을 택하며,
  # 그때는 pub 그룹의 AZ 수가 private 그룹 최대 AZ 수 이상이어야 한다(모듈의 precondition).
  single_nat_gateway = true

  # 공용 개발 계정에서 실수 삭제의 마지막 방어선이다(`CLAUDE.md` 참조).
  # ⚠️ 이걸 켜면 teardown 이 **2단계**가 된다: 이 값을 false 로 apply → destroy 워크플로.
  #    결함이 아니라 보호의 정의다. 절차는 모듈 repo `docs/04-teardown.md`가 소유한다.
  # ⛔ false 로 바꾼 커밋을 main 에 남겨두지 않는다 — 파기가 끝나면 즉시 되돌린다.
  deletion_protection = false
}

# ── 크로스 계정 네트워크 경로 — Transit Gateway (모듈 repo docs/02-choose-your-path.md
#    「네트워크 경로」 절) ─────────────────────────────────────────────────────────
#
# IAM 신뢰(live/dev/eks 의 cross-account-trust-role)는 "누가 인증되는가"만 답한다.
# private-only 엔드포인트에서 허브 ArgoCD 가 spoke API 서버에 패킷을 보낼 경로 자체가
# 없으면 인증이 성립해도 도달하지 못한다 — 이 리소스들이 그 경로다.
#
# ⛔ **VPC Peering 이 아니다.** 처음엔 Peering 을 시도했으나 AWS 가
#    "Failed due to ... overlapping CIDR range" 로 즉시 거부했다. 이
#    VPC 의 pod-dup 대역(100.64.0.0/16)을 모든 스포크가 그대로 재사용하는 설계라, 실제
#    라우팅 대상(uniq 대역)이 안 겹쳐도 dup 대역이 겹치는 것만으로 peering 자체가 거부된다.
#    자세한 근거는 모듈 repo 문서 참조.
# ── TGW 자체는 live/hub/tgw root 소관이다 ───────────────────────────────────────────
#
# TGW가 이 root와 같은 apply에서 새로 생기면, 아래 spoke 자동 발견 로직의 for_each가
# "TGW ID가 plan 시점에 unknown"이라 Invalid for_each argument로 실패한다(hub를 완전히
# destroy한 뒤 재배포할 때 재현됨). 배포 순서는 live/hub/tgw root가 먼저다.
#
# ⚠️ **state 필터가 필수다** — AWS는 destroy된 TGW도 한동안 State=deleted로
#    DescribeTransitGateways에 계속 반환한다(이미 destroy한 TGW의 유령 항목이 tag:Name
#    필터만으로는 그대로 매칭된 전례가 있다). 그 유령 항목의 route table은
#    당연히 없어 아래 aws_ec2_transit_gateway_route_table 조회가 "no matching" 에러를 낸다.
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

# transit-gateway-id 필터만으로 유일하게 좁혀진다 — live/hub/tgw의 TGW는
# default_route_table_association/propagation = "disable"이라 자동 생성되는 default RT가
# 없고, 명시로 만든 라우트테이블 하나만 존재한다.
data "aws_ec2_transit_gateway_route_table" "hub" {
  filter {
    name   = "transit-gateway-id"
    values = [data.aws_ec2_transit_gateway.hub.id]
  }
}

data "aws_caller_identity" "current" {}

# ── 허브 자신의 attachment — ArgoCD(argocd-application-controller)가 도는 서브넷 ──────
# VPC(위 module.vpc)가 있어야 만들 수 있어 live/hub/tgw로 옮길 수 없다(순환 의존).
resource "aws_ec2_transit_gateway_vpc_attachment" "hub" {
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.subnet_ids_by_group["node-uniq"]
  transit_gateway_id = data.aws_ec2_transit_gateway.hub.id

  tags = {
    Name = "tgwa-${var.workload}-${var.env}-${var.region_code}-main"
  }
}

# 두 attachment 모두 replace_existing_association 로 옛 묵시적 기본 RT(default_route_table_association
# 이 "enable" 이던 시절 자동 연결됐다)에서 우리 RT 로 옮긴다.
#
# ⚠️ hub 자신의 attachment 에도 이 방식을 쓴다 — attachment 리소스의
# transit_gateway_default_route_table_association = false 로 먼저 시도했으나 실제로는 무동작
# 이었다("Modifications complete after 0s" 뒤에도 옛 RT 연결이 그대로 남아
# AssociateTransitGatewayRouteTable 이 Resource.AlreadyAssociated 로 실패). AWS 공식 문서의
# "두 리소스로 같은 연결을 관리하지 말라"는 경고와도 맞아 — 이 인자를 걷어내고
# replace_existing_association 하나로 통일한다.
#
# spoke 의 attachment 는 애초에 RAM 으로 "받은" 쪽이라 그 인자 자체를 못 쓴다(AWS 공식 문서:
# "This cannot be configured or perform drift detection with Resource Access Manager shared
# EC2 Transit Gateways") — 이래저래 hub(TGW owner)가 명시적 연결 리소스로 양쪽을 끌어와야 한다.
resource "aws_ec2_transit_gateway_route_table_association" "hub" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.hub.id
  transit_gateway_route_table_id = data.aws_ec2_transit_gateway_route_table.hub.id
  replace_existing_association   = true
}

# ── spoke 자동 발견 — 이 TGW 에 RAM 으로 붙은 attachment 전부 ──────────────────────────
# 복수형 데이터소스는 "없으면 빈 리스트"다(단수형과 달리 에러가 아니다) — spoke 가 하나도
# 없어도, 여러 개여도 이 apply 는 그대로 성공한다. repo 변수로 spoke 의 attachment ID 를
# 수동 전달받던 방식을 걷어낸다 — 다음 spoke 를 추가할 때 이 파일을
# 고치지 않아도 되는 것이 목적이다(모듈 repo docs/02-choose-your-path.md 「네트워크 경로」
# 「값 발견」 절).
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

# ⚠️ 허브 자신의 attachment도 이 for_each에 포함된 채로 발견된다 — 이름을
# "spoke"가 아니라 "discovered"로 둔 이유다. attachment ID로 허브 것을 미리 제외하지 않는다 —
# 그 ID(aws_ec2_transit_gateway_vpc_attachment.hub.id)는 이 apply에서 새로 생기는 값이라
# plan 시점엔 여전히 unknown이고, 그걸 for_each 조건에 섞으면 위 TGW 분리로 없앤 버그가
# 그대로 재현된다. 아래 local.spoke_attachments 에서 vpc_owner_id(항상 known-at-plan)로
# 걸러낸다.
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
  # 옛 묵시적 기본 RT 에서 옮겨온 이력이 있는 spoke(dev)를 위해 유지한다 — 이미 우리 RT 에
  # 정확히 연결된 spoke 에는 no-op 이라 신규 spoke 에도 그대로 재사용해도 안전하다.
  replace_existing_association = true
}

# ⚠️ **CIDR 은 태그에서 읽지 않는다** — EC2·RAM 태그는 종류를 가리지 않고
#    계정 경계를 못 넘는다(describe-tags·DescribeTransitGatewayVpcAttachments 모두 cross-account
#    조회 시 빈 배열/null 을 반환한다, aws_ram_resource_share 데이터소스의 tags 도 마찬가지).
#    대신 attachment 의 vpc_owner_id(태그가 아니라 EC2 API 고유 속성이라 cross-account 로도
#    보인다)로 spoke 를 식별해 아래 지도에서 CIDR 을 찾는다. hub 는 spoke 마다
#    RAM 초대를 보내려면 이미 계정 ID 를 알아야 하므로(live/hub/tgw 의
#    aws_ram_principal_association) — 같은 자리에 CIDR 하나만 더 적는다. 새 수동 단계가
#    아니라 기존 단계의 확장이다.
locals {
  spoke_uniq_cidrs = {
    (var.spoke_account_id) = "10.51.0.0/16" # dev(asset 계정) — live/dev/networking 의 cidr_uniq
  }
}

# 허브 VPC 라우트테이블(node-uniq·vm-uniq — 둘 다 실제 hub→spoke 트래픽 발생원이다:
# node 는 ArgoCD 파드가 SNAT 되어 나가는 소스, vm-uniq 는 workbench 자신의 소스)에서
# 발견된 spoke 마다 라우트를 하나씩 얹는다.
# ⚠️ route_table_ids_by_group[...] 는 AZ 별 RT 리스트라 (RT × spoke) 곱집합을 만든다.
#
# ⚠️ **key 는 attachment ID 가 아니라 spoke_account_id 로 고정한다** — 이전엔
# keys(data.aws_ec2_transit_gateway_vpc_attachment.spoke) 를 그대로 key 에 섞어
# 썼는데, attachment ID 는 spoke 를 destroy→재배포할 때마다 새로 발급되는 "원격 API가
# 만드는 값"이다. Terraform 공식 문서(language/meta-arguments/for_each)가 정확히 이 패턴을
# 피하라고 명시한다 — for_each 의 key 는 리소스의 실제 주소(type.name[key])가 되므로,
# key 가 바뀌면 이 리소스 자체가 destroy+create 로 강제 교체된다. 이 route 의 실제
# 인자(destination_cidr_block·transit_gateway_id)는 애초에 attachment ID 와 무관한데도
# 그 불안정한 값을 key 에 섞은 탓에 spoke 재배포마다 불필요하게 파괴·재생성됐고, 그
# destroy 단계가 AWS API 응답 지연(5분 delete 타임아웃, aws_route 문서 기본값)에 걸려
# 실제로 apply 가 실패한 전례가 있다(live/hub/networking 재적용 중 재현됨).
# spoke_account_id 는 설정값이라 재배포해도 안 바뀐다 — 이 key 로 바꾸면 spoke 를 몇 번
# 갈아엎어도 이 리소스는 그대로 유지되고(0 changes), 이 버그 클래스 자체가 사라진다.
# attachment 존재 여부는 key 가 아니라 필터 조건으로만 쓴다(그 spoke 가 지금 실제로
# 붙어있을 때만 route 를 만든다).
locals {
  hub_rt_x_spoke = setproduct(
    toset(concat(
      module.vpc.route_table_ids_by_group["node-uniq"],
      module.vpc.route_table_ids_by_group["vm-uniq"],
    )),
    [for account_id, cidr in local.spoke_uniq_cidrs : account_id
      if contains(
        [for a in local.spoke_attachments : a.vpc_owner_id],
        account_id,
    )]
  )
}

resource "aws_route" "vpc_to_spoke" {
  for_each = { for pair in local.hub_rt_x_spoke : "${pair[0]}-${pair[1]}" => pair }

  route_table_id         = each.value[0]
  destination_cidr_block = local.spoke_uniq_cidrs[each.value[1]]
  transit_gateway_id     = data.aws_ec2_transit_gateway.hub.id

  # AWS 공식 문서(aws_route)의 delete 기본 타임아웃은 5m — 위 key 안정화로 이 리소스가
  # replace 되는 경우는 이제 거의 없어야 하지만, 예외적으로 필요할 때를 대비한 안전망이다.
  timeouts {
    delete = "15m"
  }

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.hub]
}

# ── TGW 라우트테이블 — hub 가 소유한다(TGW owner 만 자기 라우트테이블에 라우트를
#    넣을 수 있다는 AWS 제약, 모듈 repo 설계 문서 참조). 자동 전파를 껐으므로(위) 두
#    방향 모두 정적 라우트로 명시해야 한다.
#
# hub CIDR → hub 자신의 attachment. 이 값은 이미 hub state 안에 있어 지금 바로 만들 수
# 있다(spoke → hub 방향이 이 apply 로 뚫린다).
resource "aws_ec2_transit_gateway_route" "hub_via_hub_attachment" {
  destination_cidr_block         = local.cidr_uniq # hub 자신의 값 — 이 파일 상단 locals 에 이미 있다
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.hub.id
  transit_gateway_route_table_id = data.aws_ec2_transit_gateway_route_table.hub.id

  depends_on = [aws_ec2_transit_gateway_route_table_association.hub]
}

# 발견된 spoke 마다 TGW 라우트테이블에 라우트를 하나씩 얹는다 — 대상 CIDR 은 위
# local.spoke_uniq_cidrs 에서 vpc_owner_id 로 찾는다. spoke 가 늘어도(지도에 계정 ID·CIDR
# 한 줄만 추가하면) 이 리소스 블록 자체는 그대로다(for_each 가 알아서 늘어난다).
resource "aws_ec2_transit_gateway_route" "tgw_rt_to_spoke" {
  for_each = local.spoke_attachments

  destination_cidr_block         = local.spoke_uniq_cidrs[each.value.vpc_owner_id]
  transit_gateway_attachment_id  = each.value.id
  transit_gateway_route_table_id = data.aws_ec2_transit_gateway_route_table.hub.id

  depends_on = [aws_ec2_transit_gateway_route_table_association.spoke]
}

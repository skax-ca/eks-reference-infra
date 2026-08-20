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
  #    실제 대역을 재조회해 비어 있는 것을 골랐다(2026-08-19, hub 신설 시점 전 VPC CIDR 전수 조회.
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
  # uniq 대역만 정적 라우트(아래)로 명시한다.
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

# ── 허브 자신의 attachment — ArgoCD(argocd-application-controller)가 도는 서브넷 ──────
resource "aws_ec2_transit_gateway_vpc_attachment" "hub" {
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.subnet_ids_by_group["node-uniq"]
  transit_gateway_id = aws_ec2_transit_gateway.hub.id

  # TGW 의 묵시적 기본 라우트테이블에 자동 연결되지 않게 한다 — 아래
  # aws_ec2_transit_gateway_route_table_association 이 명시적으로 우리 RT 에 붙인다.
  # (hub 는 이 TGW 의 소유자라 이 인자를 쓸 수 있다 — RAM 으로 "받는" 쪽인 spoke 는
  # AWS 공식 문서상 이 인자를 못 쓴다, 아래 참조.)
  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  tags = {
    Name = "tgwa-${var.workload}-${var.env}-${var.region_code}-main"
  }
}

resource "aws_ec2_transit_gateway_route_table_association" "hub" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.hub.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.hub.id
}

# spoke 의 attachment 는 RAM 으로 "받은" 쪽이라 transit_gateway_default_route_table_association
# 인자를 못 쓴다(AWS 공식 문서: "This cannot be configured or perform drift detection with
# Resource Access Manager shared EC2 Transit Gateways") — hub(TGW owner)가 대신 끌어와야 한다.
# replace_existing_association = true 인 이유: spoke 의 attachment 는 이미 TGW 의 옛 묵시적
# 기본 RT 에 연결된 상태였다(default_route_table_association 이 "enable" 이던 시절 생성돼
# 자동 연결됐다) — 그 기존 연결을 제거하고 우리 RT 로 옮긴다.
resource "aws_ec2_transit_gateway_route_table_association" "spoke" {
  transit_gateway_attachment_id  = var.spoke_tgw_attachment_id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.hub.id
  replace_existing_association   = true
}

# 허브 VPC 라우트테이블(node-uniq)에 spoke 의 node-uniq CIDR(10.51.0.0/16, live/dev/networking
# 의 cidr_uniq) 로 가는 경로를 얹는다. ⚠️ route_table_ids_by_group["node-uniq"] 는 AZ 별
# RT 리스트다(private 그룹) — 전부에 건다.
resource "aws_route" "to_spoke_dev" {
  for_each = toset(module.vpc.route_table_ids_by_group["node-uniq"])

  route_table_id = each.value
  # 🔑 spoke 의 cidr_uniq 값이다(live/dev/networking/main.tf 참조) — 결정적 상수라 하드코딩한다.
  #    CIDR 은 계정 식별 정보가 아니다(이미 그 파일에 평문으로 커밋돼 있다) — 계정 ID 와
  #    다르게 var 로 빼지 않는다.
  destination_cidr_block = "10.51.0.0/16"
  transit_gateway_id     = aws_ec2_transit_gateway.hub.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.hub]
}

# ── TGW 라우트테이블 — hub 가 소유한다(TGW owner 만 자기 라우트테이블에 라우트를
#    넣을 수 있다는 AWS 제약, 모듈 repo 설계 문서 참조). 자동 전파를 껐으므로(위) 두
#    방향 모두 정적 라우트로 명시해야 한다.
#
# hub CIDR → hub 자신의 attachment. 이 값은 이미 hub state 안에 있어 지금 바로 만들 수
# 있다(spoke → hub 방향이 이 apply 로 뚫린다).
resource "aws_ec2_transit_gateway_route" "hub_via_hub_attachment" {
  destination_cidr_block         = "10.53.0.0/16" # hub 자신의 cidr_uniq — 위 locals 참조
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.hub.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.hub.id

  depends_on = [aws_ec2_transit_gateway_route_table_association.hub]
}

# spoke CIDR → spoke 의 attachment. spoke 의 attachment ID(AWS 무작위 부여, 결정적 합성
# 불가)는 spoke 가 자기 계정에서 attachment 를 만든 뒤 apply 로 받아 repo 변수로 전달했다
# (live/dev/networking 의 tgw_attachment_id 출력, 2026-08-20) — 이 라우트로 hub → spoke
# 방향이 완성돼 양방향 라우팅이 끝난다.
resource "aws_ec2_transit_gateway_route" "spoke_via_spoke_attachment" {
  destination_cidr_block         = "10.51.0.0/16" # spoke(dev) 의 cidr_uniq — live/dev/networking 참조
  transit_gateway_attachment_id  = var.spoke_tgw_attachment_id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.hub.id

  depends_on = [aws_ec2_transit_gateway_route_table_association.spoke]
}

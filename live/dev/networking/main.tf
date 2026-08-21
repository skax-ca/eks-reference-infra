# live/dev/networking — VPC 배포 루트
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
  #    실제 대역을 조회해 비어 있는 것을 골랐다(VPC 23개의 연결 CIDR 전수 조회):
  #      사용 중 · 10.0/16  10.10/16  10.10/21  10.20/16  10.38/16  10.90/16  10.100/16
  #                10.200/20  10.236.56/23  20.0/16  100.0/16  100.100/16  110.0/26
  #                172.30/16  172.31/16  192.168/16  210.0/16
  #      우리 것 · 10.50.0.0/24 · 10.51.0.0/16 · 100.64.0.0/16  → 어느 것과도 겹치지 않는다
  #
  #    겹침 자체가 지금 장애를 만들지는 않는다(peering·TGW 가 없다). 그러나 이 repo 는
  #    **고객사에 복사해 줄 형태**라, 겹치는 대역을 예시로 남기면 그대로 복사돼 나간다.
  cidr_primary = "10.50.0.0/24"  # uniq 소형 — ep·tgw 전용
  cidr_uniq    = "10.51.0.0/16"  # uniq — 라우팅 가능(온프레미스 도달 가정)
  cidr_dup     = "100.64.0.0/16" # dup 허용 — 비라우팅(RFC 6598)

  # ── cidrsubnet() 파생 ───────────────────────────────────────────────────────
  # 계산의 소유가 **모듈이 아니라 소비자 루트**다. 고객사는 이 locals 를 복사해 자기 대역으로 고친다.
  #
  # 겹침은 AWS API 가 apply 시 거부하므로(plan 으로는 안 잡힌다) 배치를 표로 남긴다:
  #
  #   vm-uniq    /20 × 2  10.51.0.0/20      10.51.16.0/20
  #   pub-uniq   /24 × 2  10.51.32.0/24     10.51.33.0/24    ┐
  #   elb-uniq   /24 × 2  10.51.34.0/24     10.51.35.0/24    │ 모두 10.51.32.0/20 안에서
  #   node-uniq  /24 × 2  10.51.36.0/24     10.51.37.0/24    │ 파생 — 겹치지 않는다
  #   data-uniq  /24 × 3  10.51.38.0/24 …   10.51.40.0/24    │
  #   db-uniq    /26 × 2  10.51.41.0/26     10.51.41.64/26   ┘ (/24 하나를 다시 /26 으로)
  #   pod-dup    /18 × 2  100.64.0.0/18     100.64.64.0/18
  #   ep-uniq    /27 × 2  10.50.0.0/27      10.50.0.32/27    ┐ primary /24 안에서
  #   tgw-uniq   /28 × 3  10.50.0.192/28 …  10.50.0.224/28   ┘ 앞/뒤로 떨어뜨려 배치
  # ── EKS 클러스터 이름 (live/dev/eks 루트와 공유하는 결정적 상수) ────────────
  # 🔑 이 문자열은 live/dev/eks 루트가 모듈에 넘기는 purpose="main"·serial="01" 조합과
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
  # {demo, dev, an2} → vpc-demo-dev-an2-main · snet-demo-dev-an2-pub-uniq-a
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

      # Karpenter discovery 의 **subnet 절반**. SG 절반은 EKS 모듈(live/dev/eks)이 붙인다.
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
  # ⚠️ 이 이름의 EKS 클러스터는 아직 없다(live/dev/eks 가 apply 되면 생긴다). 태그가 먼저 붙는 것은
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

# ── TGW 연결 — spoke(dev) 측 ────────────────────────────────────────────────
# hub 가 소유한 TGW 에 이 VPC 를 붙인다(모듈 repo docs/02-choose-your-path.md 「네트워크
# 경로」 절). IAM 신뢰(cross-account-trust-role)는 "누가 인증되는가"만 답하고, 이 리소스들이
# 허브 ArgoCD 가 spoke API 서버에 패킷을 보낼 실제 경로다.
#
# hub 의 TGW ID 는 repo 변수로 받지 않는다 — RAM 공유를 **이름으로** 조회한다(2026-08-20
# 재설계). 이름은 hub main.tf 의 name 조합과 동일한 공식이라 결정적이다. 값이 없으면
# (=hub 가 아직 없으면) 이 data 소스가 즉시 에러로 실패한다 — "hub 가 spoke 보다 먼저
# 존재해야 한다"는 순서를 사람이 기억하지 않아도 되게 강제하는 가드다.
#
# ⚠️ CIDR 은 **태그**로 조회하지 않는다 — 태그는 종류를 가리지 않고 계정 경계를 못 넘는다
#    (2026-08-20 실측: describe-tags·DescribeTransitGatewayVpcAttachments·
#    aws_ram_resource_share 의 tags 전부 cross-account 조회 시 빈 배열/null). 대신 CIDR 을
#    담은 관리형 접두사 목록(managed prefix list) 자체를 RAM 으로 공유받는다 — resource_arns
#    (TGW·프리픽스 리스트 둘 다)는 RAM 의 본래 목적이라 다르게 동작해 그대로 쓸 수 있다.
data "aws_ram_resource_share" "hub_tgw" {
  name           = "ram-${var.workload}-hub-${var.region_code}-tgw-share"
  resource_owner = "OTHER-ACCOUNTS"
}

locals {
  # resource_arns 에 공유된 리소스 ARN 이 전부 들어있다(TGW + 허브 uniq CIDR 프리픽스 리스트,
  # 2026-08-20 이후 2종) — 타입별 substring 으로 걸러 각자의 ID 를 잘라낸다.
  hub_transit_gateway_id = split("/", [
    for arn in data.aws_ram_resource_share.hub_tgw.resource_arns :
    arn if strcontains(arn, ":transit-gateway/")
  ][0])[1]

  # 허브의 uniq CIDR(10.53.0.0/16)을 담은 관리형 접두사 목록 — hub networking 이 만들어 같은
  # RAM 공유에 실어 보낸다. 아래 aws_route.to_hub 가 CIDR 텍스트 대신 이 ID 를 참조한다 —
  # 값 자체를 몰라도 되고, 허브의 CIDR 이 바뀌어도 이 파일을 고칠 필요가 없다.
  hub_uniq_prefix_list_id = split("/", [
    for arn in data.aws_ram_resource_share.hub_tgw.resource_arns :
    arn if strcontains(arn, ":prefix-list/")
  ][0])[1]
}

# 초대를 먼저 수락해야 한다 — allow_external_principals = true 설계라(hub main.tf 참조)
# 조직 내부 자동 공유가 아니라 표준 계정 간 공유(초대)로 동작한다.
resource "aws_ram_resource_share_accepter" "tgw" {
  share_arn = data.aws_ram_resource_share.hub_tgw.arn
}

resource "aws_ec2_transit_gateway_vpc_attachment" "spoke" {
  # 초대를 수락해야 공유된 TGW 가 attach 대상으로 보인다.
  depends_on = [aws_ram_resource_share_accepter.tgw]

  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.subnet_ids_by_group["tgw-uniq"]
  transit_gateway_id = local.hub_transit_gateway_id

  tags = {
    Name = "tgwa-${var.workload}-${var.env}-${var.region_code}-main"
  }
}

# 이 VPC 라우트테이블(node-uniq)에 hub 의 node-uniq CIDR(hub 의 cidr_uniq) 로 가는 경로를
# 얹는다. ⚠️ route_table_ids_by_group["node-uniq"] 는 AZ 별 RT 리스트다(private 그룹) — 전부에 건다.
#
# 🔴 for_each 는 **정적으로 알려진 인덱스**(0..len-1)를 키로 쓴다 — 리스트 자체(module 출력)를
#    키로 쓰지 않는다. VPC 를 이 apply 안에서 처음 만드는 경우(완전 신규 spoke) 라우트테이블
#    ID 는 apply 시점에야 정해져 리스트 전체가 "known after apply"가 되고, 그런 값을 for_each
#    키로 쓰면 OpenTofu 가 "Invalid for_each argument"로 plan 자체를 거부한다(2026-08-21 실측 —
#    2026-08-19 최초 배포 때는 이 hub 라우트가 없어 한 번도 안 겪었던 경로). local.node_cidrs
#    의 길이(정적 값)로 인덱스 집합만 만들고, 실제 라우트테이블 ID는 apply 시점에 그 인덱스로
#    조회한다 — for_each는 **키 집합**만 plan 시점에 알려지면 되고 값은 몰라도 된다.
resource "aws_route" "to_hub" {
  for_each = toset([for idx in range(length(local.node_cidrs)) : tostring(idx)])

  route_table_id = module.vpc.route_table_ids_by_group["node-uniq"][tonumber(each.value)]
  # 🔑 CIDR 텍스트를 하드코딩하지 않는다 — 허브가 RAM 으로 공유한 관리형 접두사 목록(위
  #    local.hub_uniq_prefix_list_id)을 대상으로 참조한다. AWS 가 그 ID 뒤의 실제 CIDR 을
  #    apply 시점에 풀어 쓴다. aws_route 는 destination_cidr_block 과 destination_prefix_list_id
  #    를 동시에 받지 않는다 — 이 전환은 기존 라우트를 교체(destroy 후 create)한다(레거시
  #    리소스의 공통 특성, docs/deployment-facts.md 「5.8」 참조) — 재적용 중 짧게 끊긴다.
  destination_prefix_list_id = local.hub_uniq_prefix_list_id
  transit_gateway_id         = aws_ec2_transit_gateway_vpc_attachment.spoke.transit_gateway_id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.spoke]
}

# ⚠️ **hub → spoke 방향은 이 apply 로 끝나지 않지만, attachment ID 를 손으로 옮길 필요는
#    없다.** TGW 라우트테이블은 TGW owner(hub)만 고칠 수 있어(AWS 제약) 이 attachment 를
#    hub 쪽에서 직접 만들 수는 없다. 대신 hub 는 자기 TGW 에 붙은 attachment 전부를
#    데이터소스로 자동 발견한다(live/hub/networking main.tf 「spoke 자동 발견」 참조,
#    vpc_owner_id 로 CIDR 을 식별) — hub 의 정기 plan/apply(또는 spoke 배포 직후 재실행)가
#    저절로 이 attachment 를 찾아낸다. 허브 uniq 프리픽스 리스트는 hub 의 1차 apply 때 이미
#    만들어져 있으므로(TGW·RAM 공유와 같은 블록) 이 값 발견에는 순서가 하나 더 늘지 않는다.

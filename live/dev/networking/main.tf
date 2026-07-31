# live/dev/networking — VPC 배포 루트
#
# 모듈 repo examples/vpc-enterprise 를 **착수 템플릿으로 복사**해 이 계정의 대역에 맞춘 것이다.
# 그 예제의 목적은 검증이 아니라 착수 템플릿이고(examples/vpc-enterprise/README.md), 이 파일이
# 그 용법의 첫 실제 인스턴스다.
#
# ⚠️ minimal(examples/vpc) 이 아니라 enterprise 를 택한 결과로 **첫 apply 의 판정 범위가 넓어진다**
#    — secondary CIDR 2개와 isolated 라우팅이 실제로 만들어지기 때문이다.
#    무엇이 판정되고 무엇이 안 되는지는 docs/deployment-facts.md §5 가 표로 관리한다.
#    표에 없는 것을 "검증했다"고 쓰지 않는다(CLAUDE.md §7).

locals {
  # ── CIDR 3계층 (모듈 repo design/10 §1.5(b)) ───────────────────────────────
  #
  # primary 는 인프라 전용 소형으로 최소화하고 워크로드는 secondary 에 배치한다.
  #
  # ⚠️ 이 값들은 예제에서 **그대로 가져오지 않았다.** 대상 계정이 공용 개발 계정(F13)이라
  #    실제 대역을 조회해 비어 있는 것을 골랐다(2026-07-31 실측, VPC 23개의 연결 CIDR 전수):
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

  # ── cidrsubnet() 파생 (design/10 D2) ───────────────────────────────────────
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
  # ⛔ 소싱 URL 은 git::https:// **하나로 유지한다**(D20). 인증은 CI 에서만 insteadOf 로 주입되고
  #    이 코드는 인증 방식을 모른다. SSH URL 로 바꾸면 로컬/CI 갈래가 생긴다.
  # ⛔ ?ref= 는 **정확 태그 핀**이다. git 소싱에 ~> 는 동작하지 않는다 —
  #    업그레이드는 이 줄을 올리는 명시적 커밋이고, 그 커밋이 곧 승격 게이트다.
  source = "git::https://github.com/skax-ca/iac-module-library.git//modules/vpc?ref=vpc-v1.0.0"

  # 소비자는 리소스 타입 약어를 타이핑하지 않는다 — 모듈이 조합한다(02 §1.4(b)).
  # {ref, dev, an2} → vpc-ref-dev-an2-main · snet-ref-dev-an2-pub-uniq-a
  naming = {
    workload    = var.workload
    env         = var.env
    region_code = var.region_code
  }
  purpose = "main"

  cidr_block            = local.cidr_primary
  secondary_cidr_blocks = [local.cidr_uniq, local.cidr_dup]

  # D7 — 기본 AZ 는 a·c 로 두고 3AZ 그룹만 b 를 추가로 쓴다(서울 리전 관례).
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
    # 온프레미스 왕복 경로는 TGW 운영 라우트가 추가될 때 생긴다(D3 의 의도된 순서).
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

    # EKS 노드(D9 custom networking) — node-SNAT 의 소스이자 방화벽 오픈 단위.
    "node-uniq" = {
      type  = "private"
      cidrs = local.node_cidrs
    }

    # EKS Pod 전용(D9, ENIConfig). Pod 의 VPC 외부 egress 는 노드 primary ENI 로 SNAT 되어
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
    # IP 소모 프로파일이 다르기 때문이다(D8). 라우팅은 db 와 같으므로 분리 근거가 아니다.
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
    # attachment 없는 AZ 의 리소스는 TGW 에 도달하지 못한다(공식, D6).
    "tgw-uniq" = {
      type  = "isolated"
      cidrs = local.tgw_cidrs
    }
  }

  # D4 — eks_role 이 지정된 그룹(pub-uniq · elb-uniq)에만 cluster 태그가 함께 붙는다.
  # ⚠️ 이 이름의 EKS 클러스터는 **아직 없다.** 태그가 먼저 붙는 것은 무해하고 의도된 순서다 —
  #    서브넷 디스커버리 태그는 클러스터 생성 시점에 이미 있어야 한다.
  eks_cluster_name = "eks-${var.workload}-${var.env}-${var.region_code}-main"

  # dev 는 비용 우선 — NAT 1개를 전 AZ 가 공유한다. prd 는 false(AZ별 NAT)로 가용성을 택하며,
  # 그때는 pub 그룹의 AZ 수가 private 그룹 최대 AZ 수 이상이어야 한다(D6 precondition).
  single_nat_gateway = true

  # D12 — 공용 계정(F13)에서 실수 삭제의 마지막 방어선이다(CLAUDE.md §4-1).
  # ⚠️ 이걸 켜면 teardown 이 **2단계**가 된다: deletion_protection = false 로 apply →
  #    vpc_enabled = false 로 apply. 결함이 아니라 보호의 정의다(모듈 변수 문서).
  deletion_protection = true
}

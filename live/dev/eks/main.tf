# live/dev/eks — EKS 배포 루트 (networking 과 **독립 state**: dev/eks.tfstate)
#
# 모듈 repo examples/eks-cluster-enterprise 를 착수 템플릿으로 삼되, 예제가 VPC 와 EKS 를 한 루트에
# 번들한 것과 달리 **이 repo 는 두 루트로 쪼갠다**(사용자 결정: vpc·eks 독립 배포).
#
# 독립 배포의 두 축:
#   ① state 분리 — backend.tf 의 키가 dev/eks.tfstate. 이 루트는 networking state 를 **읽지 않는다**.
#   ② 결합은 태그 data source 로만 — remote_state 참조를 쓰지 않는다(networking/outputs.tf 주석 · 03 §3.1).
#      네이밍이 결정적이라 조회가 예측 가능하다. 이 방식이면 vpc 를 먼저 파기해도 eks plan 이
#      "VPC 없음"으로 **명확히** 실패하고(조용한 오작동이 아니다), 순서만 지키면 각자 배포·파기된다.
#
# ⚠️ 소싱 핀은 정확 태그다(D20). eks-cluster-v1.0.0 = 모듈 repo a530b74. 업그레이드는 이 줄을 올리는
#    명시적 커밋이고 그것이 승격 게이트다. git 소싱에 ~> 는 동작하지 않는다.

locals {
  # 클러스터 이름 토큰. 모듈이 "eks-<workload>-<env>-<region>-<purpose>-<serial>" 로 조합한다
  # → eks-ref-dev-an2-main-01.
  #
  # 🔑 **이 두 값이 만드는 이름은 networking 루트의 eks_cluster_name 과 정확히 같아야 한다.**
  #    VPC 가 그 이름으로 서브넷 디스커버리 태그(kubernetes.io/cluster/<name> · karpenter.sh/discovery)를
  #    붙이고, EKS 모듈도 같은 이름으로 node SG 태그를 붙인다. 한 글자라도 어긋나면 selector 가
  #    빈 결과를 내고 프로비저닝이 **에러 없이** 실패한다(모듈 주석의 "PoC 실제 사고").
  #    실제 이름은 module.eks 가 소유하며 outputs.tf 의 cluster_name 으로 확인한다.
  cluster_purpose = "main"
  cluster_serial  = "01"

  # 우리 VPC 를 식별하는 Name 태그. networking 루트가 vpc 모듈에 purpose="main" 으로 넘긴 결과다.
  vpc_name = "vpc-${var.workload}-${var.env}-${var.region_code}-main"
}

# ── VPC 디스커버리 (독립 배포의 핵심) ──────────────────────────────────────────
# networking state 를 읽지 않고 Name 태그로 우리 VPC 를 찾는다. 공용 계정(F13)이라 Workload 태그로
# 한 번 더 좁혀 **남의 VPC 를 잡지 않게** 한다 — 계정에 VPC 23개가 공존한다(CLAUDE.md §4-1).
data "aws_vpc" "this" {
  filter {
    name   = "tag:Name"
    values = [local.vpc_name]
  }
  filter {
    name   = "tag:Workload"
    values = [var.workload]
  }
}

# 노드 서브넷 — SubnetGroup 태그(vpc-v1.2.0 D13)로 그룹 단위 조회한다. vpc-id 로 우리 VPC 안으로
# 한정하지 않으면 같은 태그 키를 쓰는 남의 서브넷을 잡을 수 있다(공용 계정).
data "aws_subnets" "node" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.this.id]
  }
  filter {
    name   = "tag:SubnetGroup"
    values = ["node-uniq"]
  }
}

# Pod ENI 서브넷 — custom networking(D9, ENIConfig). dup 대역(100.64/16)이라 온프레미스로
# 라우팅되지 않는다. 노드는 아래 subnet_ids 의 uniq 대역 IP 로 SNAT 된다.
data "aws_subnets" "pod" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.this.id]
  }
  filter {
    name   = "tag:SubnetGroup"
    values = ["pod-dup"]
  }
}

module "eks" {
  source = "git::https://github.com/skax-ca/iac-module-library.git//modules/eks-cluster?ref=eks-cluster-v1.0.0"

  # 소비자는 리소스 타입 약어를 타이핑하지 않는다 — 모듈이 조합한다(02 §1.4(b)).
  naming = {
    workload    = var.workload
    env         = var.env
    region_code = var.region_code
  }
  purpose = local.cluster_purpose
  serial  = local.cluster_serial

  # ── VPC 결합 — 위 data source 결과만 넘긴다(remote_state 아님) ───────────────
  vpc_id     = data.aws_vpc.this.id
  subnet_ids = data.aws_subnets.node.ids

  # ── custom networking (VPC D9) ─────────────────────────────────────────────
  enable_custom_networking = true
  pod_subnet_ids           = data.aws_subnets.pod.ids

  # ── 엔드포인트 — public-restricted (사용자 결정 2026-08-03) ──────────────────
  # public 을 켜되 CIDR 로 좁힌다. private 도 함께 켜 노드·VPC 내부 경로를 유지한다.
  # ⚠️ bastion(design/40)이 아직 없어 private-only 면 kubectl 도달 지점이 없다 — 그래서 public 을 켠다.
  endpoint_private_access = true
  endpoint_public_access  = true
  public_access_cidrs     = var.public_access_cidrs

  # ── 컨트롤플레인 로깅 (trivy AVD-AWS-0038) ─────────────────────────────────
  # CloudWatch 비용이 발생하지만 감사 대상 환경에서 audit·authenticator 는 사실상 필수다.
  enabled_log_types = ["api", "audit", "authenticator"]

  # ── 삭제 보호 (D-EKS-PROTECT) — AWS 네이티브, 콘솔에서도 안 지워진다 ─────────
  # ⚠️ teardown 은 2단계다: deletion_protection = false 로 apply → cluster_enabled = false.
  #    공용 계정(F13)에서 실수 삭제의 방어선. VPC 의 prevent_destroy 와 같은 취지지만 더 강하다.
  deletion_protection = true

  # ── 컨트롤플레인 k8s 버전 ──────────────────────────────────────────────────
  # 배포 루트는 버전을 **명시로 소유**한다 — 올릴 때 addon 핀도 함께 갱신한다(D-ADDON-VERSION-PIN-1).
  kubernetes_version = "1.35"

  # ── 노드 (시스템 계층) — 앱·버스트는 Karpenter ──────────────────────────────
  managed_node_groups = {
    # ⚠️ Karpenter 자신도 여기 떠야 한다 — chart affinity 가 karpenter.sh/nodepool DoesNotExist 를
    #    요구해 Karpenter 가 만든 노드에는 못 뜬다(자기 자신을 부트스트랩할 수 없다).
    system = {
      instance_types = ["m6i.large"]
      min_size       = 2
      max_size       = 4
      desired_size   = 2

      # ⏸ D-NODE-AMI-PIN — **apply 전 concrete 버전으로 핀한다**(README 의 pre-apply 체크리스트).
      #    null 이면 upstream 이 매 plan 마다 최신을 해석해 apply 시 노드 롤링 교체를 유발한다.
      #    계정에 붙어 유효한 버전 문자열을 확인해야 값을 넣을 수 있어 지금은 null 로 둔다.
      ami_release_version = null
    }
  }

  # ── addon — baseline 6종에 community tier 를 opt-in 으로 **merge**(누락 != 삭제) ──
  # ⭐ 버전을 안 주면 AWS 기본 버전이 해석된다(D-ADDON-VERSION-PIN-1). 완전 고정은 addon_version 을
  #    여기 박는다(README "addon 버전 고정"). kubernetes_version 을 올릴 때 함께 갱신한다.
  cluster_addons = {
    # 컨트롤러+CRD 는 IaC addon, Issuer/Certificate CR 은 GitOps 소관이다(§1 경계).
    "cert-manager" = {}
    # 관리형 Route53. 애노테이션은 GitOps, IAM 은 아래 enable_external_dns_iam 이 만든다.
    "external-dns" = {}
  }

  # ── Karpenter · 컨트롤러 IAM ────────────────────────────────────────────────
  # helm 설치·NodePool/NodeClass 는 GitOps 소관이고 IAM 전제만 IaC 가 만든다(§1 경계).
  # ⚠️ node SG 의 karpenter.sh/discovery 태그는 이 모듈이 붙이고, **노드 서브넷 태그는
  #    networking 루트가 붙인다**(node-uniq extra_tags). 둘 다 local.cluster_name 이어야 한다.
  enable_karpenter = true

  # ALBC 는 community addon 이 없어 GitOps helm 으로 설치되지만 IAM 전제는 IaC 소관이다(§2.6a).
  enable_alb_controller_iam = true

  enable_external_dns_iam = true
  # ⚠️ **prd 에서는 반드시 zone ARN 을 좁힌다.** 비우면 커뮤니티 정책이 전체 zone(*)을 허용한다.
  #    dev 는 아직 hosted zone 을 이 루트가 소유하지 않아 비워 둔다 — 이 줄을 지우고 넘어가지 않는다.
  external_dns_hosted_zone_arns = []
}

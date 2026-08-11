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
# ⚠️ 소싱 핀은 정확 태그다(D20). eks-cluster-v0.4.0 = 모듈 repo ade89e9. 업그레이드는 이 줄을 올리는
#    명시적 커밋이고 그것이 승격 게이트다. git 소싱에 ~> 는 동작하지 않는다.
# ⚠️ 0.y.z 는 개발 단계다(모듈 repo architecture/05 = D-VERSION) — 마이너 업그레이드도 계약을
#    바꿀 수 있으니 태그를 올릴 때 릴리스 메시지를 읽는다. 구 eks-cluster-v1.0.0 은 2026-08-05
#    재매핑으로 사라졌다(같은 커밋의 v0.1.0 이 대체).

# ── 계정·partition — 클러스터 ARN 을 유도하기 위한 것뿐이다 ────────────────────
# ⛔ 이 값들을 다른 용도로 늘리지 않는다. 계정 ID 를 코드에 박지 않기 위한 조회이지
#    "계정 정보를 루트가 안다"는 뜻이 아니다(D25).
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  # 클러스터 이름 토큰. 모듈이 "eks-<workload>-<env>-<region>-<purpose>-<serial>" 로 조합한다
  # → eks-ref-dev-an2-main-01.
  #
  # 🔑 **이 두 값이 만드는 이름은 networking 루트의 eks_cluster_name 과 정확히 같아야 한다.**
  #    VPC 가 그 이름으로 서브넷 디스커버리 태그(kubernetes.io/cluster/<name> · karpenter.sh/discovery)를
  #    붙이고, EKS 모듈도 같은 이름으로 node SG 태그를 붙인다. 한 글자라도 어긋나면 selector 가
  #    빈 결과를 내고 프로비저닝이 **에러 없이** 실패한다(모듈 주석의 "PoC 실제 사고").
  #    권위 값은 여전히 module.eks 가 소유한다 — outputs.tf 의 cluster_name 으로 대조한다.
  cluster_purpose = "main"
  cluster_serial  = "01"

  # ⭐ **이 두 줄이 workbench ↔ eks 순환을 끊는다**(모듈 repo 40 §5.1-1).
  #    workbench 는 eks_cluster_name/arn 을 받고, eks 는 access_entries 에 workbench role ARN 을 받는다 —
  #    양쪽이 서로의 module 출력을 참조하면 그래프 순환이라 plan 이 죽는다.
  #    클러스터 이름·ARN 은 네이밍·리전·계정으로 **유도되므로** 루트가 직접 합성한다
  #    (03 §3.1 의 1순위 "결정적 네이밍으로 값 구성", 결합도 없음).
  #    ⇒ workbench 는 local 만 참조하고, eks 만 module.workbench 를 참조한다. 단방향.
  #
  # ⛔ local.cluster_arn 을 module.eks.cluster_arn 으로 바꾸지 말 것 — 그 순간 순환이다.
  #    합성식은 실계정 대조로 확인했다(2026-08-06):
  #      arn:aws:eks:ap-northeast-2:<account>:cluster/eks-ref-dev-an2-main-01
  cluster_name = "eks-${var.workload}-${var.env}-${var.region_code}-${local.cluster_purpose}-${local.cluster_serial}"
  cluster_arn  = "arn:${data.aws_partition.current.partition}:eks:${var.aws_region}:${data.aws_caller_identity.current.account_id}:cluster/${local.cluster_name}"

  # 우리 VPC 를 식별하는 Name 태그. networking 루트가 vpc 모듈에 purpose="main" 으로 넘긴 결과다.
  vpc_name = "vpc-${var.workload}-${var.env}-${var.region_code}-main"

  # workbench 를 놓을 서브넷 하나. workbench 는 1대라 AZ 분산이 의미 없다(40 §2.2).
  #
  # ⚠️ **sort() 가 핵심이다.** data.aws_subnets.ids 는 타입이 list 지만 순서는 AWS API 응답 순이라
  #    계약이 아니다(스키마 확인 2026-08-06). 정렬 없이 [0] 을 쓰면 조회 순서가 바뀌는 것만으로
  #    subnet_id 가 달라져 **인스턴스가 교체**된다. 어느 AZ 냐가 아니라 **결정적이냐**가 요건이다.
  #    (모듈 예제는 vpc 모듈 출력의 AZ 순 리스트에서 [0] 을 뽑는다 — 여기는 data source 라 그 순서가 없다.)
  workbench_subnet_id = sort(data.aws_subnets.vm.ids)[0]
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

# 노드 서브넷 — SubnetGroup 태그(vpc-v0.3.0 D13)로 그룹 단위 조회한다. vpc-id 로 우리 VPC 안으로
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

# 관리 호스트 서브넷 — workbench 가 여기 놓인다. private(NAT 아웃바운드)이고 node-uniq 와 **분리**돼
# 있다. 섞으면 그 대역의 karpenter.sh/discovery 태그 때문에 소유가 흐려진다(40 §구현 4).
data "aws_subnets" "vm" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.this.id]
  }
  filter {
    name   = "tag:SubnetGroup"
    values = ["vm-uniq"]
  }
}

# ── workbench — private 클러스터의 도달 지점 (모듈 repo 설계 40) ─────────────────
#
# ℹ️ **흔히 bastion host 라 부르는 것의 SSM 전용 형태다.** 이름이 다른 이유는 실물이 다르기
#    때문이다 — 인바운드가 0이라 "받아서 전달하는 요새"가 아니라 kubectl 이 깔린 **작업대**다
#    (모듈 repo `40 §2.0` = D-WORKBENCH-RENAME).
# ⛔ 구 태그 `bastion-v0.1.0` 은 **원격에서 삭제됐다**(2026-08-06). 그 핀으로 되돌리면 init 이
#    실패한다. apply 가 0회인 시점이라 옮길 수 있었다 — 한 번이라도 apply 된 뒤였다면
#    purpose 가 IAM role·SG 의 **name 인자**로 흘러가 replace 가 연쇄했을 것이다.
#
# ⚠️ workbench 는 module.eks 의 출력을 **참조하지 않는다** — 위 local.cluster_name/arn 만 쓴다(순환 해소).
module "workbench" {
  # 🔴 **인스턴스를 교체한다.** 모듈이 `user_data_replace_on_change = true` 로 의도한 계약이고
  #    v0.5.0·v0.6.0 이 **둘 다 user_data 를 바꾼다.** plan 에 `# forces replacement` 가 뜨는 것이 정상이다.
  #    · 유지: IAM role·instance profile(Access Entry **2층**) · SG ID(cluster SG ingress **3층**) ·
  #            kubeconfig(user_data 가 재생성한다) — v0.3.0·v0.4.0 apply 로 **두 번 실증됐다**
  # ⛔ 재생성 중에는 **클러스터 도달 경로가 끊긴다** — endpoint_public_access = false 라
  #    workbench 가 유일한 도달 지점이다. ArgoCD 는 클러스터 안에서 자율로 도므로 영향 없다.
  #
  # ⭐ **이번 교체는 "손으로 만든 상태"를 코드가 인수하는 두 번째 회수다**(2026-08-11).
  #    v0.5.0 **D-WORKBENCH-KUBECONFIG** — kubeconfig 정본을 `0444` 로 잠그고 `/etc/skel` 로
  #      상속시켜 **사용자마다 자기 사본**을 갖게 한다. 실측 근거 두 가지:
  #        · `/home/ssm-user` 는 부팅보다 **2시간 37분 뒤**에 생긴다(SSM Agent 가 첫 세션에서
  #          `useradd -m`) ⇒ user_data 는 "그 사용자의 홈"에 아무것도 놓을 수 없다
  #        · 🔴 이 인스턴스의 공유 kubeconfig 가 실제로 **0666(world-writable)** 이 되어 있었고
  #          기본 네임스페이스가 전역 오염돼 있었다. kubeconfig 는 `users[].user.exec` 로 임의
  #          명령을 지정할 수 있어 **로컬 권한 상승 경로**다 — 편의가 아니라 보안 문제다
  #    v0.6.0 **D-WORKBENCH-TOOLING** — `eks-node-viewer`·`krew`(플러그인 6종)·로그인 프로파일.
  #
  # 🔑 instance_type 을 여기서 지정하지 않는다 — **모듈 기본값이 안전한 값이어야** 고객사가
  #    그대로 써도 부팅이 성공한다. 이 루트가 덮어쓰면 그 계약을 검증하지 못한다.
  #    (v0.4.0 이 t4g.nano → t4g.small 로 올려 v0.3.0 의 dnf OOM 부분 실패를 닫은 것이 그 사례다.)
  source = "git::https://github.com/skax-ca/iac-module-library.git//modules/workbench?ref=workbench-v0.6.0&depth=1"

  naming = {
    workload    = var.workload
    env         = var.env
    region_code = var.region_code
  }

  vpc_id    = data.aws_vpc.this.id
  subnet_id = local.workbench_subnet_id

  # ⛔ D-WORKBENCH-AMI-PIN — 모듈에 기본값이 **없다**(AMI ID 는 리전 종속이라 재사용 자산의 기본값이
  #    될 수 없다). 조회한 값을 커밋한다 — SSM latest 경로를 코드에 넣으면 AWS 릴리스마다
  #    **리뷰 없이 인스턴스가 재생성**된다. 위 ami_release_version 핀과 같은 성격이다.
  #
  # AL2023 arm64 / ap-northeast-2 (2026-08-06 실측):
  #   aws ssm get-parameter --profile team --region ap-northeast-2 \
  #     --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64 \
  #     --query Parameter.Value --output text
  # ⚠️ instance_type 기본값 t4g.small(arm64)과 **아키텍처가 짝이다.** 모듈은 검증하지 않고
  #    불일치는 apply 에서야 드러난다 — x86 으로 바꾸려면 위 경로의 -x86_64 를 조회하고
  #    instance_type 도 함께 넘긴다(노드그룹의 ami_type ↔ instance_types 와 같은 함정).
  ami_id = "ami-0973292651cddee46"

  # 클러스터 마이너와 맞춘다(1.35 → v1.35.x). https://dl.k8s.io/release/stable-1.35.txt 실측.
  kubectl_version = "v1.35.7"

  # ⚠️ 이 자리에는 *"helm 은 받지 않는다 — GitOps(pull) 전제라 helm 직접 운영(22 §3 프로파일 B)이
  #    현재 요구가 아니다"* 라고 적혀 있었다. **그 전제가 뒤집혔다**: `23` 이 self-managed ArgoCD 를
  #    workbench 에서 `helm install` 로 seed 하기로 정하면서 helm 은 **프로파일과 무관하게 필수**가 됐다.
  #    실제로 2026-08-07 seed 때 helm 이 없어 손으로 설치했고, 그 상태는 인스턴스와 함께 사라진다.
  # 핀의 SSOT 는 모듈 repo `23 §5` 다. ⛔ 최신은 v4 계열이지만 **일부러 v3** 다 —
  #    chart argo-cd 10.3.0 은 helm 3 시대 산물이고, 최초 부트스트랩에 메이저 CLI 변경까지 겹치면
  #    실패 시 원인이 둘로 갈린다(진단 가능성도 비용 항목이다).
  helm_version = "v3.21.3"

  # ⭐ chart appVersion 과 **같은 값**이다(`23 §5`). 다른 값을 핀하면 "UI 에서 되는데 CLI 에서
  #    안 된다"를 진단할 근거가 사라진다. ⚠️ chart 를 올리면 이 핀도 같이 올린다.
  # 용도는 "로그인해서 쓴다"가 아니다:
  #  ① ✅ **판정 ③ 종결**(2026-08-10) — `argocd admin cluster stats -n argocd` 로 cluster Secret 이
  #     내장 in-cluster 를 **대체**함을 확인했다(중복 아님). kubectl 로는 절반만 봤던 항목이다.
  #     ⭐ `argocd admin` 계열은 API 서버가 아니라 **k8s 를 직접 읽어 port-forward 도 login 도 없다.**
  #  ② `argocd account update-password` — seed 완료 조건(`23 §2.3`).
  #     🔴 **정정**: 이 자리에 *"port-forward·대화형 SSM 세션 없이 끝낸다"* 고 적었는데 **틀렸다.**
  #     `argocd-server` 는 **ClusterIP** 라(실측) workbench 에서는 **CLI 가 있어도 port-forward 가
  #     필요**하다. CLI 가 없애는 것은 **브라우저 UI 의존과 운영자 노트북까지의 터널**이다 —
  #     port-forward 가 인스턴스 로컬 루프백으로 축소된다.
  #     ⛔ 그리고 **대화형 세션으로 한다**: 새 비밀번호를 send-command 에 실으면 평문으로
  #     CloudTrail·히스토리에 남는다. **기술 제약이 아니라 비밀 취급**이다.
  argocd_version = "v3.5.0"

  # ── 진단·조작 도구 (v0.6.0 D-WORKBENCH-TOOLING, 모듈 repo `40 §4.3-2`) ─────────
  #
  # 노드별 CPU/메모리 할당과 비용을 한 화면에서 본다 — Karpenter 가 만든 노드가 실제로
  # 어떻게 채워졌는지 보는 용도다(같은 판정을 kubectl 로 하면 명령이 여러 개 필요하다).
  # ⚠️ 릴리스 자산 이름이 `_Linux_x86_64` 라 다른 도구의 `amd64` 와 다르다 — 모듈이 매핑한다.
  eks_node_viewer_version = "v0.7.4"

  # krew 는 `KREW_ROOT=/usr/local/krew` 로 **시스템 설치**된다(모듈이 처리).
  # ⭐ 기본값 `$HOME/.krew` 였다면 user_data 가 root 라 `/root/.krew` 에 갇혔을 것이다 —
  #    v0.5.0 이 kubeconfig 에서 고친 것과 **같은 함정, 반대 정답**이다: 플러그인은 *상태* 가
  #    아니라 *바이너리* 라 사용자별 사본이 아니라 **공유가 옳다.**
  # ⛔ 플러그인 목록(ctx·ns·neat·rbac-tool·view-secret·whoami)은 **모듈 기본값을 그대로 받는다** —
  #    같은 값을 여기 다시 적으면 모듈이 세트를 바꿀 때 조용히 어긋난다(중복은 곧 drift다).
  krew_version = "v0.5.0"

  # EKS 접근 3층 중 **1층만** 여기서 성립한다(D-WORKBENCH-SEAM).
  # 2층(Access Entry)·3층(cluster SG ingress)은 아래 eks 블록이 소유한다.
  eks_cluster_name = local.cluster_name
  eks_cluster_arn  = local.cluster_arn
}

module "eks" {
  source = "git::https://github.com/skax-ca/iac-module-library.git//modules/eks-cluster?ref=eks-cluster-v0.4.0&depth=1"

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

  # ── 엔드포인트 — **private-only** (2026-08-06 전환 완료) ─────────────────────
  #
  # apiserver 에 도달하는 유일한 경로가 **VPC 내부**다. 인터넷에서 이 클러스터의 컨트롤플레인은
  # 존재하지 않는 것과 같다 — 조작은 module.workbench 를 통해서만 이뤄진다.
  #
  # ⏱️ **전환 순서가 안전에 직결됐다.** 이 줄을 workbench 보다 먼저 바꿨다면 workbench 가
  #    동작하지 않을 때 클러스터에 닿을 방법이 아예 없었다. 그래서 다음 순서로 갔다:
  #      ① workbench apply(run 31059712680) ② SSM PingStatus Online ③ kubectl get nodes 성공
  #      ④ 그리고 나서 이 전환. ③ 까지가 전부 **선행 조건**이었다.
  #
  # 🔑 **이 전환 자체가 판정이다.** ③ 은 public 이 켜진 채로 났으므로 "private 경로로 닿았다"를
  #    증명하지 않았다 — public 을 통해 닿고 있었을 가능성이 남는다. 닫은 뒤 workbench 에서
  #    kubectl 이 다시 되는 것이 그 배제의 유일한 방법이다.
  #
  # ⛔ 되돌리려면 **workbench 가 유일한 도달 지점**임을 먼저 기억한다. public 을 다시 여는 것은
  #    설계 목적(모듈 repo 40 §1)을 되돌리는 일이므로, 접근이 필요하면 workbench 를 고친다.
  #    ⚠️ `public_access_cidrs` 는 넘기지 않는다 — public 이 꺼져 있으면 EKS 가 무시하는 값이라
  #       남겨 두면 "좁혀 두었다"는 착시만 만든다(죽은 설정).
  endpoint_private_access = true
  endpoint_public_access  = false

  # ── EKS 접근 3층 중 2·3층 — D-WORKBENCH-SEAM (모듈 repo 설계 40 §5) ────────────
  #
  # 🔑 소유가 갈리는 기준은 **주체냐 대상이냐**다. 1층(eks:DescribeCluster)은 workbench 자신의
  #    권한이라 workbench 모듈이, 2·3층은 "클러스터가 누구를 받아들이는가"라 이 모듈이 소유한다
  #    (03 §2.3 — 소유 모듈이 허용 소스를 변수로 파라미터화한다).
  #
  # ⚠️ 세 층이 **모두** 있어야 kubectl 이 닿는다. 빠뜨렸을 때 증상이 층마다 다르다:
  #      1층 없음 → update-kubeconfig 권한 오류 / 2층 없음 → 401 Unauthorized
  #      3층 없음 → dial tcp …: i/o timeout   ← 인증 계층에 닿지도 못했다는 뜻
  #    PoC 는 앞의 두 층만 갖추고 timeout 을 만났다(40 §3). 진단 시 이 표를 먼저 본다.

  # 2층 — 클러스터 안에서 무엇을 할 수 있는가.
  # ⚠️ ClusterAdmin 은 넓다. **SSM 접근 통제가 곧 클러스터 보안이 된다**(40 §10-1).
  #    실제 운영이 요구하는 최소 권한은 첫 수행 후 좁힌다(40 §10-3) — 지금 좁히면 무엇이
  #    필요한지 모른 채 추측으로 닫는 것이다.
  access_entries = {
    workbench = {
      principal_arn = module.workbench.workbench_iam_role_arn
      policy_associations = {
        admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }

  # 3층 — apiserver 에 네트워크로 닿는가. eks-cluster-v0.3.0 이 신설한 통과 지점이다.
  cluster_security_group_additional_rules = {
    workbench_kubectl = {
      from_port                = 443
      to_port                  = 443
      description              = "kubectl from workbench"
      source_security_group_id = module.workbench.workbench_security_group_id
    }
  }

  # ── 컨트롤플레인 로깅 (trivy AVD-AWS-0038) ─────────────────────────────────
  # CloudWatch 비용이 발생하지만 감사 대상 환경에서 audit·authenticator 는 사실상 필수다.
  enabled_log_types = ["api", "audit", "authenticator"]

  # ── 삭제 보호 (D-EKS-PROTECT) — AWS 네이티브, 콘솔에서도 안 지워진다 ─────────
  # ⚠️ teardown 은 2단계다: 이 값을 false 로 apply → destroy 워크플로.
  #    공용 계정(F13)에서 실수 삭제의 방어선. VPC 의 prevent_destroy 와 같은 취지지만 더 강하다.
  # ⛔ false 로 바꾼 커밋을 main 에 남겨두지 않는다 — 파기가 끝나면 즉시 되돌린다.
  deletion_protection = true

  # ── 컨트롤플레인 k8s 버전 ──────────────────────────────────────────────────
  # 배포 루트는 버전을 **명시로 소유**한다 — 올릴 때 addon 핀도 함께 갱신한다(D-ADDON-VERSION-PIN-1).
  kubernetes_version = "1.35"

  # ── 노드 (시스템 계층) — 앱·버스트는 Karpenter ──────────────────────────────
  managed_node_groups = {
    # ⚠️ Karpenter 자신도 여기 떠야 한다 — chart affinity 가 karpenter.sh/nodepool DoesNotExist 를
    #    요구해 Karpenter 가 만든 노드에는 못 뜬다(자기 자신을 부트스트랩할 수 없다).
    system = {
      # graviton(arm64). dev 비용 우선이라 system 계층이 감당 가능한 가장 작은 크기를 쓴다 —
      # 이 노드가 Karpenter + core addon + 컨트롤러(cert-manager·external-dns·ALBC·ebs-csi)를 얹는다.
      # ⚠️ 더 줄이면(t4g.small = 2 GiB) kubelet+daemonset 몫을 빼고 남는 여유가 거의 없다.
      instance_types = ["t4g.medium"]
      min_size       = 2
      max_size       = 4
      desired_size   = 2

      # ⭐ D-NODE-ARCH — **instance_types 와 짝이다.** t4g(arm64)를 쓰면서 이 줄을 빼면 기본값이
      #    x86 이라 AMI 와 CPU 가 어긋나 **노드가 부팅되지 않는다.** 이 불일치는 plan 에서 잡히지
      #    않는다(AWS 도 노드그룹 생성 시점에야 거부한다) — 둘을 항상 함께 고친다.
      ami_type = "AL2023_ARM_64_STANDARD"

      # D-NODE-AMI-PIN — null 이면 upstream 이 매 plan 마다 최신을 해석해 apply 마다 노드 롤링
      # 교체를 유발한다. 업그레이드는 이 값을 올리는 명시적 커밋이어야 plan diff 로 리뷰된다.
      # ⚠️ **아키텍처별로 값이 다르다.** arm SSM 경로에서 얻은 값이다(2026-08-04 실측):
      #   aws ssm get-parameter --profile team --region ap-northeast-2 \
      #     --name /aws/service/eks/optimized-ami/1.35/amazon-linux-2023/arm64/standard/recommended/release_version
      # ⚠️ kubernetes_version 을 올리면 이 값도 함께 갱신한다.
      ami_release_version = "1.35.6-20260728"
    }
  }

  # ── addon — baseline 6종 버전 override + community tier 2종 opt-in(누락 != 삭제) ──
  #
  # ⭐ **버전 값은 이 배포 루트가 소유한다**(D-ADDON-VERSION-PIN-1). 모듈은 버전을 들지 않는다 —
  #    addon 상향은 워크로드 운영 주기에 속하고, 공통 모듈이 값을 들면 우리 kube-proxy 상향이
  #    모듈 릴리스를 요구해 다른 고객사에게도 배송된다.
  # ℹ️ addon_version 만 적어도 **모듈 소유 필드는 살아남는다** — vpc-cni 의 custom networking 구성과
  #    ebs-csi 의 pod identity association 은 merge **뒤에** 재주입된다(모듈 addons.tf §4).
  # ⚠️ 여기 안 적은 addon 도 사라지지 않는다(누락 != 삭제). 제거는 enabled = false 명시로만 하고,
  #    core 4종(vpc-cni·coredns·kube-proxy·eks-pod-identity-agent)은 그것마저 차단된다.
  #
  # 🔴 값의 정의역: **f(kubernetes_version, region)**. 아래는 **k8s 1.35 · ap-northeast-2 기준**
  #    (2026-08-04 실측). kubernetes_version 을 올리면 **이 표도 함께 갱신**한다 — 안 하면
  #    "그 버전 없음"으로 apply 가 죽는다(kube-proxy 는 정의상 k8s 마이너를 따라간다).
  #    조회: aws eks describe-addon-versions --kubernetes-version 1.35 --region ap-northeast-2 \
  #            --addon-name <name> --profile team \
  #            --query 'addons[0].addonVersions[?compatibilities[0].defaultVersion==`true`].addonVersion | [0]'
  #
  # 🔑 **최신이 아니라 AWS 기본(default) 버전을 박았다.** 기본을 박으면 핀 전후 동작이 같다 —
  #    핀은 "지금 상태를 고정"하는 일이다. 최신을 박으면 이 커밋에 **업그레이드 결정이 섞인다.**
  #    상향은 값을 올리는 별도 커밋이어야 plan diff 로 리뷰된다.
  #    (실측 차이: coredns 기본 v1.13.2-eksbuild.11 ≠ 최신 v1.14.3-eksbuild.3)
  cluster_addons = {
    # ── baseline 6종 (버전만 override) ──────────────────────────────────────
    "vpc-cni"                = { addon_version = "v1.22.3-eksbuild.1" }
    "coredns"                = { addon_version = "v1.13.2-eksbuild.11" }
    "kube-proxy"             = { addon_version = "v1.35.3-eksbuild.17" }
    "eks-pod-identity-agent" = { addon_version = "v1.3.10-eksbuild.3" }
    "aws-ebs-csi-driver"     = { addon_version = "v1.63.1-eksbuild.1" }
    "metrics-server"         = { addon_version = "v0.9.0-eksbuild.5" }

    # ── community tier (opt-in 추가) ────────────────────────────────────────
    # 컨트롤러+CRD 는 IaC addon, Issuer/Certificate CR 은 GitOps 소관이다(§1 경계).
    "cert-manager" = { addon_version = "v1.21.0-eksbuild.3" }
    # ⛔ external-dns 는 **싣지 않는다**(2026-08-05). 아래 enable_external_dns_iam 과 한 쌍이다 —
    #    IAM 없이 컨트롤러만 돌면 Route53 에 아무것도 쓰지 못하는 파드가 남는다(죽은 경로).
    #    되켤 때는 addon 과 IAM 을 **함께** 켠다.
  }

  # ── Karpenter · 컨트롤러 IAM ────────────────────────────────────────────────
  # helm 설치·NodePool/NodeClass 는 GitOps 소관이고 IAM 전제만 IaC 가 만든다(§1 경계).
  # ⚠️ node SG 의 karpenter.sh/discovery 태그는 이 모듈이 붙이고, **노드 서브넷 태그는
  #    networking 루트가 붙인다**(node-uniq extra_tags). 둘 다 local.cluster_name 이어야 한다.
  enable_karpenter = true

  # ALBC 는 community addon 이 없어 GitOps helm 으로 설치되지만 IAM 전제는 IaC 소관이다(§2.6a).
  enable_alb_controller_iam = true

  # ⛔ **끈 상태가 기본값이다**(2026-08-05 개정). 2026-08-04 에는 "임시 끄기"였지만, 모듈이
  #    v0.2.0 에서 가드를 갖게 되면서 성격이 바뀌었다 — 이제 이것이 소비 프로젝트의 기본값이다
  #    (모듈 repo `design/20 §4.2` = D-EXTDNS-ZONE, 예제 README "external-dns" 절).
  #
  #    원인: external_dns_hosted_zone_arns=[] 를 넘기면 upstream 이 Resource="*" 인 IAM 정책을
  #    만드는데, route53:ChangeResourceRecordSets 는 리소스 수준 권한이라 AWS 가
  #    400 MalformedPolicyDocument 로 거부한다.
  #
  #    ⛔ **upstream fix 를 기다리지 않는다** — upstream 버그가 아니라 AWS IAM 제약이다.
  #       모듈 v0.2.0 이 이 조합을 **plan 에서** 거부하므로, 이제 zone ARN 없이 켜면
  #       apply 가 아니라 plan 단계에서 막힌다.
  #
  #    되켜는 법: dev hosted zone 을 확보한 뒤 data.aws_route53_zone 으로 **조회**해서 ARN 을
  #    넘기고, 위 cluster_addons 의 "external-dns" 도 **함께** 되살린다. zone 자체는 이 루트가
  #    소유하지 않는다 — 워크로드 수명주기보다 오래 살기 때문이다(03 §3.1).
  enable_external_dns_iam = false
}

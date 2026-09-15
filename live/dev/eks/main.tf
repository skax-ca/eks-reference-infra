# live/dev/eks: EKS 배포 루트 (spoke). networking과 독립 state(dev/eks.tfstate)다.
#
# VPC와 EKS를 두 루트로 쪼갠다. 이 루트는 networking state를 읽지 않고 태그 data source로만
# 결합한다. 네이밍이 결정적이라 조회가 예측 가능하고, vpc를 먼저 파기하면 eks plan이 "VPC 없음"
# 으로 명확히 실패한다(조용한 오작동이 아니다).
# ⚠️ 소싱 핀은 정확 태그다. git 소싱에 ~>는 동작하지 않고, 0.y.z는 마이너 업그레이드도 계약을
#    바꿀 수 있으니 태그를 올릴 때 릴리스 메시지를 읽는다.
#
# 설계 근거: iac-module-library docs/architectures/gitops-hub-spoke/aws/README.md
# 모듈 계약: iac-module-library docs/module-catalog.md

# 클러스터 ARN을 유도하기 위한 조회다.
# ⛔ 이 값들을 다른 용도로 늘리지 않는다. 계정 ID를 코드에 박지 않기 위한 조회이지 "계정
#    정보를 루트가 안다"는 뜻이 아니다.
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  # 모듈이 "eks-<workload>-<env>-<region>-<purpose>-<serial>"로 조합한다 → eks-demo-dev-an2-main-01.
  # ⚠️ 이 두 값이 만드는 이름은 networking 루트의 eks_cluster_name과 정확히 같아야 한다. VPC가
  #    그 이름으로 서브넷 디스커버리 태그(kubernetes.io/cluster/<name>·karpenter.sh/discovery)를
  #    붙이고 EKS 모듈도 같은 이름으로 node SG 태그를 붙인다. 한 글자라도 어긋나면 selector가
  #    빈 결과를 내고 프로비저닝이 에러 없이 실패한다. 권위 값은 module.eks가 소유하므로
  #    outputs.tf의 cluster_name으로 대조한다.
  cluster_purpose = "main"
  cluster_serial  = "01"

  # 이 두 줄이 workbench ↔ eks 순환을 끊는다. workbench는 eks_cluster_name/arn을 받고 eks는
  # access_entries에 workbench role ARN을 받는데, 양쪽이 서로의 module 출력을 참조하면 그래프
  # 순환이라 plan이 죽는다. 클러스터 이름·ARN은 네이밍·리전·계정으로 유도되므로 루트가 직접
  # 합성한다. workbench는 local만 참조하고 eks만 module.workbench를 참조한다(단방향).
  # ⛔ local.cluster_arn을 module.eks.cluster_arn으로 바꾸지 않는다. 그 순간 순환이다.
  cluster_name = "eks-${var.workload}-${var.env}-${var.region_code}-${local.cluster_purpose}-${local.cluster_serial}"
  cluster_arn  = "arn:${data.aws_partition.current.partition}:eks:${var.aws_region}:${data.aws_caller_identity.current.account_id}:cluster/${local.cluster_name}"

  # 허브 ArgoCD Pod Identity Role ARN. hub는 별도 계정·별도 state라 module 출력을 참조할 수
  # 없어 결정적으로 조합한다. 이름 형태는 eks-cluster 모듈의 argocd_hub_pod_identity 네이밍과
  # 같아야 한다(iamr-demo-hub-an2-argocd-hub).
  hub_argocd_role_arn = "arn:aws:iam::${var.hub_account_id}:role/iamr-demo-hub-an2-argocd-hub"

  # networking 루트가 vpc 모듈에 purpose="main"으로 넘긴 결과다.
  vpc_name = "vpc-${var.workload}-${var.env}-${var.region_code}-main"

  # workbench는 1대라 AZ 분산이 의미 없다.
  # ⚠️ sort()가 핵심이다. data.aws_subnets.ids는 list지만 순서는 AWS API 응답 순이라 계약이
  #    아니다. 정렬 없이 [0]을 쓰면 조회 순서가 바뀌는 것만으로 subnet_id가 달라져 인스턴스가
  #    교체된다. 어느 AZ냐가 아니라 결정적이냐가 요건이다.
  workbench_subnet_id = sort(data.aws_subnets.vm.ids)[0]

  # system 노드그룹 taint(workload-class=system:NoSchedule) 대응 toleration/nodeSelector.
  # coredns·metrics-server(Deployment)에만 쓴다(운영 절차는 docs/runbooks.md).
  # ⛔ vpc-cni·eks-pod-identity-agent에는 쓰지 않는다. 두 DaemonSet은 차트 기본 tolerations가
  #    이미 operator:Exists라 모든 taint를 통과하므로 좁은 값을 직접 쓰면 후퇴이고, vpc-cni는
  #    enable_custom_networking=true라 모듈이 configuration_values를 재주입해 반영되지도 않는다.
  workload_class_toleration = jsonencode({
    nodeSelector = { "workload-class" = "system" }
    tolerations = [
      { key = "workload-class", operator = "Equal", value = "system", effect = "NoSchedule" },
    ]
  })
}

# 허브 uniq CIDR 발견. networking과 별도 state라 같은 RAM 조회를 독립적으로 반복한다(remote_state를
# 쓰지 않는다는 원칙). 태그로는 계정 경계를 못 넘지만 RAM resource_arns는 넘는다.
data "aws_ram_resource_share" "hub_tgw" {
  name           = "ram-${var.workload}-hub-${var.region_code}-tgw-share"
  resource_owner = "OTHER-ACCOUNTS"
}

locals {
  hub_uniq_prefix_list_id = split("/", [
    for arn in data.aws_ram_resource_share.hub_tgw.resource_arns :
    arn if strcontains(arn, ":prefix-list/")
  ][0])[1]
}

# VPC 디스커버리. networking state를 읽지 않고 Name 태그로 우리 VPC를 찾는다. 공용 개발
# 계정이라 Workload 태그로 한 번 더 좁혀 남의 VPC를 잡지 않게 한다.
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

# 노드 서브넷. SubnetGroup 태그로 그룹 단위 조회한다. vpc-id로 우리 VPC 안으로 한정하지 않으면
# 같은 태그 키를 쓰는 남의 서브넷을 잡을 수 있다(공용 계정).
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

# Pod ENI 서브넷(custom networking, ENIConfig). dup 대역(100.64/16)이라 온프레미스로 라우팅되지
# 않고, 노드는 subnet_ids의 uniq 대역 IP로 SNAT된다.
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

# workbench 서브넷. private(NAT 아웃바운드)이고 node-uniq와 분리돼 있다. 섞으면 그 대역의
# karpenter.sh/discovery 태그 때문에 소유가 흐려진다.
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

# workbench: private 클러스터의 유일한 도달 지점. bastion의 SSM 전용 형태로, 인바운드가 0이라
# "받아서 전달하는 요새"가 아니라 kubectl이 깔린 작업대다.
# ⚠️ module.eks의 출력을 참조하지 않는다(위 local.cluster_name/arn만). 순환 해소.
module "workbench" {
  # ⚠️ 태그를 올리면 인스턴스가 교체된다. 모듈이 user_data_replace_on_change = true로 의도한
  #    계약이라 plan에 forces replacement가 뜨는 것이 정상이다. IAM role·instance profile(Access
  #    Entry)·SG ID(cluster SG ingress)는 유지되고 kubeconfig는 user_data가 재생성한다.
  # ⛔ 재생성 중에는 클러스터 도달 경로가 끊긴다. endpoint_public_access = false라 workbench가
  #    유일한 도달 지점이다. ArgoCD는 클러스터 안에서 자율로 도므로 영향 없다.
  # ⚠️ instance_type을 여기서 지정하지 않는다. 모듈 기본값이 안전한 값이어야 고객사가 그대로
  #    써도 부팅이 성공하는데, 이 루트가 덮어쓰면 그 계약을 검증하지 못한다.
  source = "git::https://github.com/skax-ca/iac-module-library.git//modules/aws/workbench?ref=workbench-v0.8.0&depth=1"

  naming = {
    workload    = var.workload
    env         = var.env
    region_code = var.region_code
  }

  vpc_id    = data.aws_vpc.this.id
  subnet_id = local.workbench_subnet_id

  # ⛔ 모듈에 기본값이 없다(AMI ID는 리전 종속이라 재사용 자산의 기본값이 될 수 없다). 조회한
  #    값을 커밋한다. SSM latest 경로를 코드에 넣으면 AWS 릴리스마다 리뷰 없이 인스턴스가
  #    재생성된다. 아래 ami_release_version 핀과 같은 성격이다.
  #
  # AL2023 arm64 / ap-northeast-2:
  #   aws ssm get-parameter --profile team --region ap-northeast-2 \
  #     --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64 \
  #     --query Parameter.Value --output text
  # ⚠️ instance_type 기본값 t4g.small(arm64)과 아키텍처가 짝이다. 모듈은 검증하지 않고 불일치는
  #    apply에서야 드러난다. x86으로 바꾸려면 위 경로의 -x86_64를 조회하고 instance_type도
  #    함께 넘긴다(노드그룹의 ami_type ↔ instance_types와 같은 함정).
  ami_id = "ami-0973292651cddee46"

  # 클러스터 마이너와 맞춘다(1.35 → v1.35.x). https://dl.k8s.io/release/stable-1.35.txt
  kubectl_version = "v1.35.7"

  # helm은 GitOps(pull) 전제와 무관하게 필수다. self-managed ArgoCD를 workbench에서 helm install로
  # seed하는 것이 부트스트랩 경로다(scripts/argocd-seed.sh). helm이 없으면 손으로 설치해야 하고
  # 그 상태는 인스턴스와 함께 사라진다.
  # ⛔ 최신은 v4 계열이지만 일부러 v3다. chart argo-cd 10.3.0은 helm 3 시대 산물이고, 최초
  #    부트스트랩에 메이저 CLI 변경까지 겹치면 실패 시 원인이 둘로 갈린다.
  helm_version = "v3.21.3"

  # chart appVersion과 같은 값이다. 다른 값을 핀하면 "UI에서 되는데 CLI에서 안 된다"를 진단할
  # 근거가 사라진다. 용도는 "로그인해서 쓴다"가 아니다:
  #   argocd admin cluster stats -n argocd로 cluster Secret이 내장 in-cluster를 대체함을
  #   확인한다(argocd admin 계열은 k8s를 직접 읽어 port-forward도 login도 없다).
  #   argocd account update-password가 seed 완료 조건이다.
  # ⚠️ chart를 올리면 이 핀도 같이 올린다.
  # ⚠️ argocd-server는 ClusterIP라 workbench에서도 port-forward가 필요하다. CLI가 없애는 것은
  #    브라우저 UI 의존과 운영자 노트북까지의 터널이다.
  # ⛔ 비밀번호 교체는 대화형 세션으로 한다. 새 비밀번호를 send-command에 실으면 평문으로
  #    CloudTrail·히스토리에 남는다.
  argocd_version = "v3.5.0"

  # 노드별 CPU/메모리 할당과 비용을 한 화면에서 본다(Karpenter가 만든 노드가 실제로 어떻게
  # 채워졌는지). 릴리스 자산 이름이 _Linux_x86_64라 다른 도구의 amd64와 다른데 모듈이 매핑한다.
  eks_node_viewer_version = "v0.7.4"

  # krew는 KREW_ROOT=/usr/local/krew로 시스템 설치된다(모듈이 처리). 기본값 $HOME/.krew였다면
  # user_data가 root라 /root/.krew에 갇힌다. 플러그인은 상태가 아니라 바이너리라 사용자별
  # 사본이 아니라 공유가 옳다.
  # ⛔ 플러그인 목록(ctx·ns·neat·rbac-tool·view-secret·whoami)은 모듈 기본값을 그대로 받는다.
  #    같은 값을 여기 다시 적으면 모듈이 세트를 바꿀 때 조용히 어긋난다.
  krew_version = "v0.5.0"

  # EKS 접근 3층 중 1층(eks:DescribeCluster)만 여기서 성립한다. 2층(Access Entry)·3층(cluster
  # SG ingress)은 아래 eks 블록이 소유한다.
  # ⚠️ name은 일부러 module.eks 출력에서 받는다. 이 참조가 유일한 순서 간선이다.
  #    local.cluster_name을 쓰면 값은 같지만 OpenTofu가 순서를 알 수 없어 workbench와
  #    클러스터를 병렬로 만들고, EC2는 1분·EKS는 10분이라 user_data의 update-kubeconfig가
  #    "클러스터 없음"으로 전부 실패한다.
  # ⛔ depends_on = [module.eks]로 풀지 않는다(순환). depends_on은 모듈 전체에 걸리는데
  #    module.eks는 아래에서 workbench의 IAM role ARN·SG ID를 설정 시점에 쓴다. 값 참조는
  #    리소스 단위라 고리가 닫히지 않는다: 클러스터에 매달리는 것은 인스턴스, module.eks가
  #    받아가는 것은 role·SG다.
  eks_cluster_name = module.eks.cluster_name

  # ⚠️ arn은 deterministic local을 유지한다(비대칭). 모듈의 aws_iam_role_policy.eks_describe는
  #    count를 eks_cluster_arn != null에 걸어 두는데, 실 ARN은 AWS가 돌려주는 값이라 plan 시점
  #    unknown이고 unknown을 count에 넣으면 plan이 깨진다. name은 우리가 정해 넣는 값이라
  #    known이다. 가르는 기준은 일관성이 아니라 plan 시점 known 여부다.
  eks_cluster_arn = local.cluster_arn
}

# 크로스 계정 신뢰 Role. 스포크가 소유한다. 허브의 self-managed ArgoCD(argocd-application-controller)가
# 이 Role을 assume해 이 클러스터에 도달한다. IAM 정책은 "assume 가능"뿐이고 실제 K8s 권한은
# 아래 eks 블록의 access_entries가 부여한다. IAM과 K8s 권한 두 층을 분리하는 것이 최소 권한
# 설계다.
# ⚠️ 배포 순서는 허브가 먼저다. trust policy는 Principal 대상이 실제로 존재해야 AWS가 정책
#    생성을 허용한다(없으면 "Invalid principal in policy").
# ⛔ vpc/eks-cluster/workbench 체인과 독립이다. naming만 공유하고 다른 모듈 출력을 참조하지 않는다.
module "argocd_trust" {
  source = "git::https://github.com/skax-ca/iac-module-library.git//modules/aws/cross-account-trust-role?ref=cross-account-trust-role-v0.3.0&depth=1"

  naming = {
    workload    = var.workload
    env         = var.env
    region_code = var.region_code
  }
  purpose = "argocd-hub"

  trusted_principal_arns = [local.hub_argocd_role_arn]
}

module "eks" {
  source = "git::https://github.com/skax-ca/iac-module-library.git//modules/aws/eks-cluster?ref=eks-cluster-v0.10.0&depth=1"

  # 리소스 타입 약어는 모듈이 조합한다.
  naming = {
    workload    = var.workload
    env         = var.env
    region_code = var.region_code
  }
  purpose = local.cluster_purpose
  serial  = local.cluster_serial

  # VPC 결합은 위 data source 결과만 넘긴다(remote_state 아님).
  vpc_id     = data.aws_vpc.this.id
  subnet_ids = data.aws_subnets.node.ids

  # custom networking(VPC의 pod-dup 서브넷).
  enable_custom_networking = true
  pod_subnet_ids           = data.aws_subnets.pod.ids

  # 엔드포인트는 private-only다. apiserver에 도달하는 유일한 경로가 VPC 내부이고 조작은
  # module.workbench를 통해서만 이뤄진다.
  # ⚠️ public을 닫기 전에 workbench apply → SSM PingStatus Online → kubectl get nodes 성공이
  #    먼저다. 닫은 뒤 workbench에서 kubectl이 다시 되는 것이 "private 경로로 닿았다"의 유일한
  #    증명이다(public이 켜진 채로는 그 경로로 닿고 있었을 가능성이 남는다).
  # ⛔ public을 다시 열지 않는다. 접근이 필요하면 workbench를 고친다.
  # ⚠️ public_access_cidrs는 넘기지 않는다. public이 꺼져 있으면 EKS가 무시하는 값이라
  #    "좁혀 두었다"는 착시만 만든다.
  endpoint_private_access = true
  endpoint_public_access  = false

  # EKS 접근 3층 중 2·3층. 소유가 갈리는 기준은 주체냐 대상이냐다. 1층은 workbench 자신의
  # 권한이라 workbench 모듈이, 2·3층은 "클러스터가 누구를 받아들이는가"라 이 모듈이 소유한다.
  # ⚠️ 세 층이 모두 있어야 kubectl이 닿는다. 빠뜨렸을 때 증상이 층마다 다르다:
  #      1층 없음 → update-kubeconfig 권한 오류 / 2층 없음 → 401 Unauthorized
  #      3층 없음 → dial tcp …: i/o timeout(인증 계층에 닿지도 못했다는 뜻)

  # 2층: 클러스터 안에서 무엇을 할 수 있는가.
  # ⚠️ ClusterAdmin은 넓다. SSM 접근 통제가 곧 클러스터 보안이 된다. 최소 권한은 실제 운영이
  #    요구하는 것을 안 뒤에 좁힌다.
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

    # 허브 ArgoCD 크로스 계정 접근. AWS 관리형 access policy로 부여한다. ArgoCD가 애드온·CRD 등
    # 클러스터 스코프 리소스 전반을 다뤄야 해 세밀한 RBAC 범위 제어가 불필요하고, access
    # policy로 요구가 충족되면 kubernetes_groups+RBAC로 내려가지 않는다(iac-module-library
    # docs/module-catalog.md 「K8s 권한 부여 방식」).
    # ⚠️ 이 방식으로 준 권한은 kubectl auth can-i --list에 보이지 않는다.
    #    aws eks list-associated-access-policies로만 조회된다.
    argocd_hub = {
      principal_arn = module.argocd_trust.role_arn
      # ⚠️ aws_eks_access_entry.kubernetes_groups는 Optional+Computed라 이 필드를 아예 빼면(null)
      #    provider가 "의견 없음"으로 읽어 이전 상태값을 그대로 둔다. 명시적으로 빈 리스트를
      #    줘야 실제로 지워진다.
      kubernetes_groups = []
      policy_associations = {
        admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }

  # 3층: apiserver에 네트워크로 닿는가.
  cluster_security_group_additional_rules = {
    workbench_kubectl = {
      from_port                = 443
      to_port                  = 443
      description              = "kubectl from workbench"
      source_security_group_id = module.workbench.workbench_security_group_id
    }

    # hub ArgoCD가 spoke apiserver에 도달하는 경로. TGW로 라우팅된 트래픽이라(다른 VPC·다른
    # 계정) SG 참조 자체가 성립하지 않아 source_security_group_id가 아니라 prefix_list_ids를 쓴다.
    # ⚠️ hub의 cidr_uniq 값을 CIDR 텍스트로 하드코딩하지 않는다. 허브가 RAM으로 공유한 관리형
    #    접두사 목록(위 local.hub_uniq_prefix_list_id)을 참조한다. 둘 사이의 전환은 기존 규칙을
    #    교체(destroy 후 create)하므로 재적용 중 짧게 끊긴다.
    hub_argocd = {
      from_port       = 443
      to_port         = 443
      description     = "apiserver from hub ArgoCD (via TGW)"
      prefix_list_ids = [local.hub_uniq_prefix_list_id]
    }
  }

  # 컨트롤플레인 로깅(trivy AVD-AWS-0038). CloudWatch 비용이 발생하지만 감사 대상 환경에서
  # audit·authenticator는 사실상 필수다.
  enabled_log_types = ["api", "audit", "authenticator"]

  # AWS 네이티브 삭제 보호. 콘솔에서도 안 지워진다. 공용 개발 계정에서 실수 삭제의 방어선이다.
  # ⚠️ 켜면 teardown이 2단계가 된다(false로 apply → destroy 워크플로).
  # ⛔ false로 바꾼 커밋을 main에 남겨두지 않는다. 지금 false인 것은 철거·재구축 중이라서다.
  #    재구축이 끝나면 true로 되돌린다.
  deletion_protection = false

  # 배포 루트가 버전을 명시로 소유한다. 올릴 때 addon 핀·ami_release_version도 함께 갱신한다.
  kubernetes_version = "1.35"

  # 시스템 계층 노드. 앱·버스트는 Karpenter.
  managed_node_groups = {
    # ⚠️ Karpenter 자신도 여기 떠야 한다. chart affinity가 karpenter.sh/nodepool DoesNotExist를
    #    요구해 Karpenter가 만든 노드에는 못 뜬다(자기 자신을 부트스트랩할 수 없다).
    system = {
      # graviton(arm64). 비용 우선이라 system 계층이 감당 가능한 가장 작은 크기를 쓴다. 이 노드가
      # Karpenter + core addon + 컨트롤러(cert-manager·external-dns·ALBC·ebs-csi)를 얹는다.
      # ⚠️ 더 줄이면(t4g.small = 2 GiB) kubelet+daemonset 몫을 빼고 남는 여유가 거의 없다.
      instance_types = ["t4g.medium"]
      min_size       = 2
      max_size       = 4
      desired_size   = 2

      # ⚠️ instance_types와 짝이다. t4g(arm64)를 쓰면서 이 줄을 빼면 기본값이 x86이라 AMI와
      #    CPU가 어긋나 노드가 부팅되지 않는다. plan에서 잡히지 않고 AWS도 노드그룹 생성
      #    시점에야 거부한다. 둘을 항상 함께 고친다.
      ami_type = "AL2023_ARM_64_STANDARD"

      # null이면 upstream이 매 plan마다 최신을 해석해 apply마다 노드 롤링 교체를 유발한다.
      # 업그레이드는 이 값을 올리는 명시적 커밋이어야 plan diff로 리뷰된다.
      # ⚠️ 아키텍처별로 값이 다르다(arm SSM 경로):
      #   aws ssm get-parameter --profile team --region ap-northeast-2 \
      #     --name /aws/service/eks/optimized-ami/1.35/amazon-linux-2023/arm64/standard/recommended/release_version
      # ⚠️ kubernetes_version을 올리면 이 값도 함께 갱신한다.
      ami_release_version = "1.35.6-20260728"

      # Karpenter + Cluster Autoscaler 동시 운영을 위한 taint 전략의 밀어내기 축(운영 절차는
      # docs/runbooks.md). 끌어당기기 축(nodeSelector)은 이 노드그룹에 뜨는 addon·컨트롤러가
      # 각자 건다.
      # ⛔ NodePool 쪽에는 대응 taint를 두지 않는다(app 워크로드가 toleration을 몰라도 되게).
      labels = {
        "workload-class" = "system"
      }
      taints = [
        {
          key    = "workload-class"
          value  = "system"
          effect = "NO_SCHEDULE"
        },
      ]
    }
  }

  # addon: baseline 6종 버전 override + community tier opt-in.
  #
  # 버전 값은 이 배포 루트가 소유한다. addon 상향은 워크로드 운영 주기에 속하고, 공통 모듈이
  # 값을 들면 우리 kube-proxy 상향이 모듈 릴리스를 요구해 다른 고객사에게도 배송된다.
  # addon_version만 적어도 모듈 소유 필드(vpc-cni의 custom networking 구성, ebs-csi의 pod
  # identity association)는 merge 뒤에 재주입되어 살아남는다.
  # ⚠️ 여기 안 적은 addon도 사라지지 않는다(누락 != 삭제). 제거는 enabled = false 명시로만 하고,
  #    core 4종(vpc-cni·coredns·kube-proxy·eks-pod-identity-agent)은 그것마저 차단된다.
  # ⚠️ 값의 정의역은 f(kubernetes_version, region)이고 아래는 k8s 1.35·ap-northeast-2 기준이다.
  #    kubernetes_version을 올리면 이 표도 함께 갱신한다. 안 하면 "그 버전 없음"으로 apply가
  #    죽는다(kube-proxy는 정의상 k8s 마이너를 따라간다). 조회:
  #      aws eks describe-addon-versions --kubernetes-version 1.35 --region ap-northeast-2 \
  #        --addon-name <name> --profile team \
  #        --query 'addons[0].addonVersions[?compatibilities[0].defaultVersion==`true`].addonVersion | [0]'
  # ⚠️ 최신이 아니라 AWS 기본(default) 버전을 박는다. 핀은 "지금 상태를 고정"하는 일이고,
  #    최신을 박으면 그 커밋에 업그레이드 결정이 섞인다. 상향은 값을 올리는 별도 커밋이어야
  #    plan diff로 리뷰된다.
  cluster_addons = {
    # baseline 6종(버전만 override)
    "vpc-cni" = { addon_version = "v1.22.3-eksbuild.1" }
    "coredns" = {
      addon_version = "v1.13.2-eksbuild.11"
      configuration = local.workload_class_toleration
    }
    "kube-proxy"             = { addon_version = "v1.35.3-eksbuild.17" }
    "eks-pod-identity-agent" = { addon_version = "v1.3.10-eksbuild.3" }
    "aws-ebs-csi-driver" = {
      addon_version = "v1.63.1-eksbuild.1"
      # node(DaemonSet)·controller(Deployment) 스키마가 완전히 분리돼 있다. 하나만 고치면
      # 나머지가 무제약 상태로 남아 taint 적용 시 Karpenter로 밀려난다. node는 tolerateAllTaints
      # 불리언, controller는 그런 불리언이 없어 coredns·metrics-server와 같은 nodeSelector+
      # toleration으로 고정한다.
      configuration = jsonencode({
        node       = { tolerateAllTaints = true }
        controller = jsondecode(local.workload_class_toleration)
      })
    }
    "metrics-server" = {
      addon_version = "v0.9.0-eksbuild.5"
      configuration = local.workload_class_toleration
    }

    # community tier(opt-in). 컨트롤러+CRD는 IaC addon, Issuer/Certificate CR은 GitOps 소관이다.
    # ⚠️ coredns·metrics-server·ebs-csi와 달리 최상위 toleration만으로는 부족하다. cert-manager
    #    차트는 컨트롤러·cainjector·webhook 세 개의 독립된 Deployment로 구성되고(describe-addon-
    #    configuration 스키마) 각각 자기 nodeSelector·tolerations를 따로 받는다. 최상위만 주면
    #    cainjector·webhook이 system 노드그룹의 workload-class=system taint를 넘지 못해, Karpenter
    #    노드가 아직 없는 상태(GitOps 미시딩)에서 addon 전체가 DEGRADED(InsufficientNumberOfReplicas)로
    #    멈춘다.
    "cert-manager" = {
      addon_version = "v1.21.0-eksbuild.3"
      configuration = jsonencode(merge(
        jsondecode(local.workload_class_toleration),
        {
          cainjector = jsondecode(local.workload_class_toleration)
          webhook    = jsondecode(local.workload_class_toleration)
        }
      ))
    }
    # ⛔ external-dns는 싣지 않는다. 아래 enable_external_dns_iam과 한 쌍이다. IAM 없이 컨트롤러만
    #    돌면 Route53에 아무것도 쓰지 못하는 파드가 남는다. 되켤 때는 addon과 IAM을 함께 켠다.
  }

  # Karpenter. helm 설치·NodePool/NodeClass는 GitOps 소관이고 IAM 전제만 IaC가 만든다.
  # ⚠️ node SG의 karpenter.sh/discovery 태그는 이 모듈이 붙이고, 노드 서브넷 태그는 networking
  #    루트가 붙인다(node-uniq extra_tags). 둘 다 local.cluster_name이어야 한다.
  enable_karpenter = true

  # system 관리형 노드그룹 전용 오토스케일러의 IAM 전제조건(Pod Identity 연결 + ASG
  # node-template/* 태그, managed_node_groups.system의 labels·taints 미러링). helm 설치는
  # GitOps(eks-platform-gitops) 카탈로그 opt-in 소관이다. Karpenter가 담당하는 app 워크로드와는
  # 무관하고, 이 변수로만 게이트된 리소스 2개뿐이라 꺼도 Karpenter·taint 배선은 영향받지 않는다.
  enable_cluster_autoscaler = true

  # ALBC는 community addon이 없어 GitOps helm으로 설치되지만 IAM 전제는 IaC 소관이다.
  enable_alb_controller_iam = true

  # ⛔ 끈 상태가 기본값이다. external_dns_hosted_zone_arns=[]를 넘기면 upstream이 Resource="*"인
  #    IAM 정책을 만드는데 route53:ChangeResourceRecordSets는 리소스 수준 권한이라 AWS가 400
  #    MalformedPolicyDocument로 거부한다. upstream 버그가 아니라 AWS IAM 제약이고, 모듈이 이
  #    조합을 plan에서 거부한다.
  #    되켜는 법: hosted zone을 확보한 뒤 data.aws_route53_zone으로 조회해서 ARN을 넘기고, 위
  #    cluster_addons의 "external-dns"도 함께 되살린다. zone 자체는 워크로드 수명주기보다 오래
  #    살기 때문에 이 루트가 소유하지 않는다.
  enable_external_dns_iam = false
}

# live/dev/networking: VPC 배포 루트 (spoke 첫 인스턴스). VPC·서브넷·TGW attachment·hub 방향 라우트.
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
  cidr_primary = "10.50.0.0/24"  # uniq 소형, ep·tgw 전용
  cidr_uniq    = "10.51.0.0/16"  # uniq, 라우팅 가능(온프레미스 도달 가정)
  cidr_dup     = "100.64.0.0/16" # dup 허용, 비라우팅(RFC 6598)

  # cidrsubnet() 파생. 계산의 소유는 모듈이 아니라 소비자 루트다(고객사는 이 locals를 복사해
  # 자기 대역으로 고친다). 겹침은 AWS API가 apply 시에만 거부하므로 배치를 표로 남긴다:
  #
  #   vm-uniq    /20 × 2  10.51.0.0/20      10.51.16.0/20
  #   pub-uniq   /24 × 2  10.51.32.0/24     10.51.33.0/24    ┐
  #   elb-uniq   /24 × 2  10.51.34.0/24     10.51.35.0/24    │ 모두 10.51.32.0/20 안에서
  #   node-uniq  /24 × 2  10.51.36.0/24     10.51.37.0/24    │ 파생, 겹치지 않는다
  #   data-uniq  /24 × 3  10.51.38.0/24 …   10.51.40.0/24    │
  #   db-uniq    /26 × 2  10.51.41.0/26     10.51.41.64/26   ┘ (/24 하나를 다시 /26으로)
  #   pod-dup    /18 × 2  100.64.0.0/18     100.64.64.0/18
  #   ep-uniq    /27 × 2  10.50.0.0/27      10.50.0.32/27    ┐ primary /24 안에서
  #   tgw-uniq   /28 × 3  10.50.0.192/28 …  10.50.0.224/28   ┘ 앞/뒤로 떨어뜨려 배치

  # ⚠️ live/dev/eks가 모듈에 넘기는 purpose="main"·serial="01" 조합과 정확히 같아야 한다.
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

  # 리소스 타입 약어는 모듈이 조합한다. {demo, dev, an2} → vpc-demo-dev-an2-main
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

      # Karpenter discovery의 subnet 절반. SG 절반은 EKS 모듈(live/dev/eks)이 붙인다.
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
  # ⚠️ 켜면 teardown이 2단계가 된다(false로 apply → destroy 워크플로). 절차는 docs/spoke-lifecycle.md.
  # ⛔ false로 바꾼 커밋을 main에 남겨두지 않는다. 지금 false인 것은 철거·재구축 중이라서다.
  #    재구축이 끝나면 true로 되돌린다.
  deletion_protection = false
}

# TGW 연결(spoke 측). hub가 소유한 TGW에 이 VPC를 붙인다. IAM 신뢰(cross-account-trust-role)는
# "누가 인증되는가"만 답하고, 허브 ArgoCD가 spoke API 서버에 패킷을 보낼 실제 경로는 이
# 리소스들이 만든다.
#
# hub의 TGW ID는 repo 변수로 받지 않고 RAM 공유를 이름으로 조회한다. 이름은 hub의 name 조합과
# 같은 공식이라 결정적이다. 값이 없으면(hub가 아직 없으면) 이 data 소스가 즉시 실패해 "hub가
# spoke보다 먼저 존재해야 한다"는 순서를 사람이 기억하지 않아도 되게 강제한다.
#
# ⚠️ CIDR은 태그로 조회하지 않는다. 태그는 종류를 가리지 않고 계정 경계를 못 넘는다
#    (describe-tags·DescribeTransitGatewayVpcAttachments·aws_ram_resource_share의 tags 전부
#    cross-account 조회 시 빈 값). 대신 CIDR을 담은 관리형 접두사 목록 자체를 RAM으로 공유받는다.
#    resource_arns(TGW·프리픽스 리스트)는 RAM의 본래 목적이라 계정 경계를 넘는다.
data "aws_ram_resource_share" "hub_tgw" {
  name           = "ram-${var.workload}-hub-${var.region_code}-tgw-share"
  resource_owner = "OTHER-ACCOUNTS"
}

locals {
  # resource_arns에 공유된 리소스 ARN이 전부 들어있다(TGW + 허브 uniq CIDR 프리픽스 리스트).
  # 타입별 substring으로 걸러 각자의 ID를 잘라낸다.
  hub_transit_gateway_id = split("/", [
    for arn in data.aws_ram_resource_share.hub_tgw.resource_arns :
    arn if strcontains(arn, ":transit-gateway/")
  ][0])[1]

  # 허브의 uniq CIDR을 담은 관리형 접두사 목록. hub가 만들어 같은 RAM 공유에 실어 보낸다.
  # 아래 aws_route.to_hub가 CIDR 텍스트 대신 이 ID를 참조하므로 값 자체를 몰라도 되고, 허브의
  # CIDR이 바뀌어도 이 파일을 고칠 필요가 없다.
  hub_uniq_prefix_list_id = split("/", [
    for arn in data.aws_ram_resource_share.hub_tgw.resource_arns :
    arn if strcontains(arn, ":prefix-list/")
  ][0])[1]
}

# ⛔ RAM 초대 수락을 aws_ram_resource_share_accepter 리소스로 두지 않는다. CI 단계
#    (.github/workflows/deploy-dev-network.yml plan job, tofu init 이전)가 전담한다. 리소스로
#    두면 (1) delete가 DisassociateResourceShare를 직접 호출해 spoke teardown마다 hub의
#    aws_ram_principal_association을 hub state 모르게 실물에서 해제하고, (2) 재배포 때 새로
#    생기는 초대는 PENDING인데 그 상태를 조회하는 데이터소스가 없어(위 data.aws_ram_resource_share는
#    ACCEPTED 이후에만 찾는다) 스스로는 절대 수락할 수 없는 순환에 빠진다.
#
# 이 removed 블록은 state에 남아 있는 accepter를 관리 대상에서 뺀다(destroy가 아니다). apply
# 한 번으로 state에서만 잊혀지고 AWS 실물(수락 상태)은 그대로다. state에 그 리소스가 없는
# spoke에서는 no-op이다.
removed {
  from = aws_ram_resource_share_accepter.tgw
  lifecycle {
    destroy = false
  }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "spoke" {
  # depends_on이 없다. CI가 tofu init 이전에 수락을 끝내므로 이 시점엔 항상 ACTIVE고, 리소스
  # 그래프 안에 수락을 대신할 의존 대상이 없다.
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.subnet_ids_by_group["tgw-uniq"]
  transit_gateway_id = local.hub_transit_gateway_id

  tags = {
    Name = "tgwa-${var.workload}-${var.env}-${var.region_code}-main"
  }
}

# 이 VPC 라우트테이블(node-uniq, AZ별 RT 리스트라 전부)에 hub의 cidr_uniq로 가는 경로를 얹는다.
#
# ⚠️ for_each는 정적으로 알려진 인덱스(0..len-1)를 키로 쓴다. 리스트 자체(module 출력)를 키로
#    쓰면 VPC를 이 apply 안에서 처음 만드는 경우 라우트테이블 ID가 apply 시점에야 정해져 리스트
#    전체가 "known after apply"가 되고 Invalid for_each argument로 plan이 거부된다.
#    local.node_cidrs의 길이(정적 값)로 인덱스 집합만 만들고 실제 ID는 그 인덱스로 조회한다.
#    for_each는 키 집합만 plan 시점에 알려지면 되고 값은 몰라도 된다.
resource "aws_route" "to_hub" {
  for_each = toset([for idx in range(length(local.node_cidrs)) : tostring(idx)])

  route_table_id = module.vpc.route_table_ids_by_group["node-uniq"][tonumber(each.value)]
  # CIDR 텍스트를 하드코딩하지 않고 허브가 RAM으로 공유한 관리형 접두사 목록을 참조한다. AWS가
  # 그 ID 뒤의 실제 CIDR을 apply 시점에 풀어 쓴다.
  # ⚠️ aws_route는 destination_cidr_block과 destination_prefix_list_id를 동시에 받지 않는다.
  #    둘 사이의 전환은 기존 라우트를 교체(destroy 후 create)하므로 재적용 중 짧게 끊긴다.
  destination_prefix_list_id = local.hub_uniq_prefix_list_id
  transit_gateway_id         = aws_ec2_transit_gateway_vpc_attachment.spoke.transit_gateway_id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.spoke]
}

# hub → spoke 방향은 이 apply로 끝나지 않지만 attachment ID를 손으로 옮길 필요는 없다. TGW
# 라우트테이블은 TGW owner(hub)만 고칠 수 있어 이 attachment를 hub 쪽에서 직접 만들 수는 없고,
# 대신 hub가 자기 TGW에 붙은 attachment 전부를 데이터소스로 자동 발견한다(live/hub/networking,
# vpc_owner_id로 CIDR 식별). hub의 정기 plan/apply(또는 spoke 배포 직후 재실행)가 저절로 이
# attachment를 찾아낸다.

# 이 루트의 출력은 **GitOps 저장소(eks-platform-gitops)가 소비하는 앵커**다.
# EKS 는 IaC 가 클러스터·IAM 전제까지만 만들고, helm/NodePool/애플리케이션은 GitOps(pull)가 맡는다.
# 그 경계를 넘겨주는 값이 아래다 — cluster 등록 정보 · Karpenter/컨트롤러 IAM ARN.
#
# ⚠️ kill switch(cluster_enabled=false)나 opt-out 시 모듈이 null 을 돌려준다(에러 아님).
#    그래야 teardown 중에도 `tofu output` 이 성립한다.

# ── 클러스터 등록 정보 (GitOps 가 클러스터를 붙일 때) ──────────────────────────

output "cluster_name" {
  description = "EKS 클러스터 이름(권위 값 = 모듈 소유). networking 의 디스커버리 태그와 일치해야 한다."
  value       = module.eks.cluster_name
}

output "cluster_arn" {
  description = "EKS 클러스터 ARN. GitOps 클러스터 등록이 API URL 이 아니라 ARN 을 요구한다."
  value       = module.eks.cluster_arn
}

output "cluster_endpoint" {
  description = "kube-apiserver 엔드포인트 URL."
  value       = module.eks.cluster_endpoint
}

output "cluster_version" {
  description = "실제 기동된 컨트롤플레인 k8s 버전. 입력 kubernetes_version 과 대조해 승격을 확인한다."
  value       = module.eks.cluster_version
}

output "cluster_certificate_authority_data" {
  description = "kubeconfig 의 certificate-authority-data(base64)."
  value       = module.eks.cluster_certificate_authority_data
}

output "cluster_oidc_issuer_url" {
  description = "OIDC 발급자 URL."
  value       = module.eks.cluster_oidc_issuer_url
}

output "oidc_provider_arn" {
  description = "IAM OIDC 공급자 ARN(IRSA role 신뢰 정책이 참조. Pod Identity 를 쓰면 불필요)."
  value       = module.eks.oidc_provider_arn
}

# ── workbench (도달 지점) ──────────────────────────────────────────────────────
# ⚠️ GitOps 앵커가 아니라 **운영자용**이다 — private 엔드포인트로 전환하면 이 값이 클러스터를
#    만지는 유일한 출발점이 된다. workbench_enabled = false 면 null 이다(에러 아님).

output "workbench_instance_id" {
  description = <<-EOT
    SSM 접속 대상. 인바운드가 0이라 SSH 가 아니라 SSM 으로만 들어간다:
      aws ssm start-session --profile team --region ap-northeast-2 --target <id>
    kubeconfig 는 workbench user_data 가 이미 만들어 둔다(EKS 접근 3층 중 1층).
  EOT
  value       = module.workbench.workbench_instance_id
}

# ── 보안 그룹 ────────────────────────────────────────────────────────────────

output "node_security_group_id" {
  description = "노드 보안 그룹 ID. Karpenter 의 securityGroupSelectorTerms 가 이 SG 의 discovery 태그를 찾는다."
  value       = module.eks.node_security_group_id
}

# ── Karpenter (GitOps 의 NodePool/NodeClass 가 소비) ──────────────────────────
# enable_karpenter=false 또는 kill switch 면 전부 null 이다.

output "karpenter_node_iam_role_name" {
  description = "Karpenter 노드 IAM role 이름. EC2NodeClass 의 role 필드가 ARN 이 아니라 이름을 받는다."
  value       = module.eks.karpenter_node_iam_role_name
}

output "karpenter_instance_profile_name" {
  description = "Karpenter 노드 instance profile 이름."
  value       = module.eks.karpenter_instance_profile_name
}

output "karpenter_sqs_queue_name" {
  description = "스팟 중단·헬스 이벤트 SQS 큐 이름."
  value       = module.eks.karpenter_sqs_queue_name
}

output "karpenter_discovery_tag" {
  description = <<-EOT
    Karpenter discovery 태그(맵). NodeClass 의 subnetSelectorTerms·securityGroupSelectorTerms 가 쓴다.
    ⚠️ 같은 값이 networking 루트의 node-uniq extra_tags 에도 있어야 한다(양쪽 태그 = local.cluster_name).
  EOT
  value       = module.eks.karpenter_discovery_tag
}

# ── 컨트롤러 IAM (GitOps helm 의 serviceAccount 가 참조) ──────────────────────

output "alb_controller_iam_role_arn" {
  description = "AWS Load Balancer Controller 의 Pod Identity role ARN. ALBC 는 GitOps helm 으로 설치된다."
  value       = module.eks.alb_controller_iam_role_arn
}

output "external_dns_iam_role_arn" {
  # ⚠️ 현재는 **null 이다** — enable_external_dns_iam = false 가 기본값이기 때문이다(main.tf 참조).
  #    에러가 아니라 모듈의 설계된 동작이며, 되켜면 값이 채워진다.
  description = "external-dns 의 Pod Identity role ARN. 현재 external-dns 는 꺼져 있어 null 이다."
  value       = module.eks.external_dns_iam_role_arn
}

output "ebs_csi_iam_role_arn" {
  description = "EBS CSI Driver 의 Pod Identity role ARN."
  value       = module.eks.ebs_csi_iam_role_arn
}

output "effective_addon_names" {
  description = "최종 설치되는 addon 목록(baseline merge + enabled 필터). cluster_addons 병합 결과 확인점."
  value       = module.eks.effective_addon_names
}

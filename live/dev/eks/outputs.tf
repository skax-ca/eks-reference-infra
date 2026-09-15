# 이 루트의 출력은 GitOps 저장소(eks-platform-gitops)가 소비하는 앵커다. IaC는 클러스터·IAM
# 전제까지만 만들고 helm/NodePool/애플리케이션은 GitOps(pull)가 맡는다. 그 경계를 넘겨주는
# 값이 cluster 등록 정보와 Karpenter/컨트롤러 IAM ARN이다.
#
# ⚠️ kill switch(cluster_enabled=false)나 opt-out 시 모듈이 null을 돌려준다(에러 아님).
#    그래야 teardown 중에도 tofu output이 성립한다.

# 클러스터 등록 정보(GitOps가 클러스터를 붙일 때)

output "cluster_name" {
  description = "EKS 클러스터 이름(권위 값 = 모듈 소유). networking의 디스커버리 태그와 일치해야 한다."
  value       = module.eks.cluster_name
}

output "cluster_arn" {
  description = "EKS 클러스터 ARN. GitOps 클러스터 등록이 API URL이 아니라 ARN을 요구한다."
  value       = module.eks.cluster_arn
}

output "cluster_endpoint" {
  description = "kube-apiserver 엔드포인트 URL."
  value       = module.eks.cluster_endpoint
}

output "cluster_version" {
  description = "실제 기동된 컨트롤플레인 k8s 버전. 입력 kubernetes_version과 대조해 승격을 확인한다."
  value       = module.eks.cluster_version
}

output "cluster_certificate_authority_data" {
  description = "kubeconfig의 certificate-authority-data(base64)."
  value       = module.eks.cluster_certificate_authority_data
}

output "cluster_oidc_issuer_url" {
  description = "OIDC 발급자 URL."
  value       = module.eks.cluster_oidc_issuer_url
}

output "oidc_provider_arn" {
  description = "IAM OIDC 공급자 ARN(IRSA role 신뢰 정책이 참조. Pod Identity를 쓰면 불필요)."
  value       = module.eks.oidc_provider_arn
}

# workbench(도달 지점). GitOps 앵커가 아니라 운영자용이다. private 엔드포인트라 이 값이
# 클러스터를 만지는 유일한 출발점이다. workbench_enabled = false면 null이다(에러 아님).

output "workbench_instance_id" {
  description = <<-EOT
    SSM 접속 대상. 인바운드가 0이라 SSH가 아니라 SSM으로만 들어간다:
      aws ssm start-session --profile team --region ap-northeast-2 --target <id>
    kubeconfig는 workbench user_data가 이미 만들어 둔다(EKS 접근 3층 중 1층).
  EOT
  value       = module.workbench.workbench_instance_id
}

output "node_security_group_id" {
  description = "노드 보안 그룹 ID. Karpenter의 securityGroupSelectorTerms가 이 SG의 discovery 태그를 찾는다."
  value       = module.eks.node_security_group_id
}

# Karpenter(GitOps의 NodePool/NodeClass가 소비). enable_karpenter=false 또는 kill switch면
# 전부 null이다.

output "karpenter_node_iam_role_name" {
  description = "Karpenter 노드 IAM role 이름. EC2NodeClass의 role 필드가 ARN이 아니라 이름을 받는다."
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
    Karpenter discovery 태그(맵). NodeClass의 subnetSelectorTerms·securityGroupSelectorTerms가 쓴다.
    ⚠️ 같은 값이 networking 루트의 node-uniq extra_tags에도 있어야 한다(양쪽 태그 = local.cluster_name).
  EOT
  value       = module.eks.karpenter_discovery_tag
}

# 컨트롤러 IAM(GitOps helm의 serviceAccount가 참조)

output "alb_controller_iam_role_arn" {
  description = "AWS Load Balancer Controller의 Pod Identity role ARN. ALBC는 GitOps helm으로 설치된다."
  value       = module.eks.alb_controller_iam_role_arn
}

output "external_dns_iam_role_arn" {
  # enable_external_dns_iam = false라 null이다. 에러가 아니라 모듈의 설계된 동작이고 되켜면 채워진다.
  description = "external-dns의 Pod Identity role ARN. external-dns가 꺼져 있으면 null이다."
  value       = module.eks.external_dns_iam_role_arn
}

output "ebs_csi_iam_role_arn" {
  description = "EBS CSI Driver의 Pod Identity role ARN."
  value       = module.eks.ebs_csi_iam_role_arn
}

output "effective_addon_names" {
  description = "최종 설치되는 addon 목록(baseline merge + enabled 필터). cluster_addons 병합 결과 확인점."
  value       = module.eks.effective_addon_names
}

<!-- Parent: ../../../AGENTS.md -->
<!-- Generated: 2026-08-04 | Updated: 2026-08-04 -->

# live/dev/eks

## 목적
EKS 클러스터 배포 루트. `networking/`과 독립적인 state. 생성 대상: 클러스터 (Graviton), 관리형 노드 그룹 (t4g.medium, ARM64), Karpenter, 클러스터 IAM 역할, 보안 그룹. **아직 apply 안 함** — plan만 완료 (`71개 추가`).

## 주요 파일

| 파일 | 설명 |
|------|------|
| `backend.tf` | `networking/`과 같은 부분 설정 패턴 — 버킷 명은 init 시 주입 |
| `main.tf` | EKS 모듈 호출 (`eks-cluster-v0.1.0`). graviton 사용 (`ami_type = AL2023_ARM_64_STANDARD`) |
| `outputs.tf` | 클러스터 엔드포인트, kubeconfig (민감), 노드 그룹 정보 |
| `providers.tf` | AWS provider + k8s provider (향후 리소스용) |
| `variables.tf` | `ami_release_version = "1.35.6-20250728"` (ARM64 SSM 경로), `cluster_version`, `eks_cluster_name = "eks-ref-dev-an2-main-01"` |
| `versions.tf` | OpenTofu + AWS provider + helm/k8s provider 제약 |
| `README.md` | pre-apply 체크리스트 — 전부 ✅, dispatch만 남음 |

## 모듈 소싱

```hcl
source = "git::https://github.com/skax-ca/iac-module-library.git//modules/eks-cluster?ref=eks-cluster-v0.1.0"
```

## AI 에이전트 가이드

### Pre-apply 체크리스트 (2026-08-04 기준 전부 ✅)

| 항목 | 상태 | 검증 내용 |
|------|------|---------|
| ~~`EKS_PUBLIC_ACCESS_CIDRS` repo 변수~~ | ⛔ 삭제 | 2026-08-06 private-only 전환으로 불필요. ⚠️ 이 표에 **운영자 실제 IP 가 커밋돼 있었다** — D25(출발지 IP 는 git 에 두지 않는다) 위반이라 값과 함께 걷어냈다 |
| networking 먼저 apply | ✅ | 6개 서브넷 태그 변경 apply 완료 |
| `ami_release_version` 핀 | ✅ | `1.35.6-20250728` — ARM64 SSM 경로 |
| addon 버전 핀 | ✅ | `vpc-cni` · `coredns` · `kube-proxy` AWS 기본 버전으로 핀 (최신 아님) |
| 클러스터명 상수 | ✅ | `eks-ref-dev-an2-main-01` (serial `-01` 필수) |

### ⚠️ ARM64 아키텍처 (Graviton)
`ami_type = AL2023_ARM_64_STANDARD`가 모듈 facade 변수로 전달된다.
모듈 (`eks-cluster-v0.1.0`)이 이를 상위 모듈 `terraform-aws-modules/eks` (v21.24.1)에 전달한다.
**상위 모듈은 원래부터 arm64를 지원했다** — 진짜 문제는 facade가 값을 전달하지 않았던 것이었다.
x86 대비 월 약 $120 절감 (`m6i.large` × 2 대비).

### VPC 결합 (의도적, remote_state 없음)
```hcl
data "aws_vpc" "main" {
  filter { name = "tag:Name";    values = ["vpc-ref-dev-an2-main"] }
  filter { name = "tag:Workload"; values = ["ref"] }
}
data "aws_subnets" "node" {
  filter { name = "tag:SubnetGroup"; values = ["node-uniq"] }
  filter { name = "tag:Name";        values = ["sng-ref-dev-an2-main-*"] }
}
```
`terraform_remote_state` 없음 — 결합은 태그 규약으로만 이루어진다.
`networking/`이 apply되지 않으면 이 조회 결과가 비어서 plan이 명확하게 실패한다 (조용한 오작동 아님).

### Backend 설정
`networking/`과 같은 패턴: `backend.hcl` gitignored, CI에서만 `assume_role`.

## Apply 대상 (dispatch 시)

| 리소스 유형 | 개수 |
|------------|------|
| EKS 클러스터 컨트롤 플레인 | 1 |
| 클러스터 IAM 역할 | 2 |
| 보안 그룹 | 2 |
| 관리형 노드 그룹 (t4g.medium × 2) | 1 |
| Karpenter NodePool + EC2NodeClass | 2 |
| Addon 설정 (8개) + IAM | 9개 이상 |

## 비용 (apply 시)

| 항목 | 월 비용 |
|------|--------|
| EKS 컨트롤 플레인 | 약 $73 |
| t4g.medium × 2 | 약 $48 |
| 기존 NAT (networking) | +$43 |
| **추가 비용** | 약 $121 |

## 의존성

### 내부
- `live/dev/networking/`이 먼저 apply되어야 함 (태그로 VPC 조회)

### 외부
- `iac-module-library` eks-cluster 모듈 (`eks-cluster-v0.1.0`)
- `terraform-aws-modules/eks` v21.24.1 (전이적)
- S3 backend + OIDC + Roles (`bootstrap/`에서 생성)

## 제약사항

| 제약 | 메커니즘 |
|------|---------|
| **공개 접근 없음** | `endpoint_public_access = false` — apiserver 는 VPC 내부에서만 도달한다(2026-08-06) |
| Addon 안정성 | AWS 기본 버전으로 핀, 최신 아님 |
| 이 루트에서 파기禁止 | 모듈 D12의 `prevent_destroy` |

<!-- MANUAL: -->
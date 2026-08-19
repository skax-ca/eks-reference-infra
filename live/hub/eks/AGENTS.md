<!-- Parent: ../../../AGENTS.md -->
<!-- Generated: 2026-08-19 | Updated: 2026-08-19 -->

# live/hub/eks

## 목적
EKS 클러스터 배포 허브 루트. `live/dev/eks`를 템플릿으로 복사(2026-08-19, 허브-스포크 크로스 계정
IAM 설계 구현 1단계). `networking/`과 독립적인 state(`hub/eks.tfstate`). 생성 대상: 클러스터
(Graviton), 관리형 노드 그룹(t4g.medium×2~4, ARM64), Karpenter IAM 전제, 클러스터 IAM 역할,
보안 그룹, workbench. **아직 apply 안 함**(코드만 신설).

## 주요 파일

| 파일 | 설명 |
|------|------|
| `backend.tf` | `networking/`과 같은 부분 설정 패턴 — 버킷 명은 init 시 주입 |
| `main.tf` | EKS 모듈(`eks-cluster-v0.8.0`) + workbench 모듈(`workbench-v0.6.0`) 호출. graviton(`ami_type = AL2023_ARM_64_STANDARD`). `enable_argocd_hub_pod_identity = false`(스포크 부재 — 아래 「크로스 계정 확장」 참조) |
| `outputs.tf` | 클러스터 엔드포인트·kubeconfig 앵커·Karpenter/컨트롤러 IAM ARN |
| `providers.tf` | AWS provider (`session_name = tofu-live-hub-eks`) |
| `variables.tf` | `env` 기본값 `hub`(dev와 갈리는 지점) |
| `versions.tf` | OpenTofu + AWS provider 제약 |
| `README.md` | pre-apply 체크리스트(전부 미착수) |

## 모듈 소싱

정확한 태그 핀은 이 루트의 `main.tf`의 `source`가 유일한 사실(SSOT)이다 — 여기 다시 적지 않는다.

```hcl
source = "git::https://github.com/skax-ca/iac-module-library.git//modules/eks-cluster?ref=<main.tf 참조>"
```

## VPC 결합 (의도적, remote_state 없음)
```hcl
data "aws_vpc" "this" {
  filter { name = "tag:Name";     values = ["vpc-demo-hub-an2-main"] }
  filter { name = "tag:Workload"; values = ["demo"] }
}
data "aws_subnets" "node" {
  filter { name = "vpc-id";        values = [data.aws_vpc.this.id] }
  filter { name = "tag:SubnetGroup"; values = ["node-uniq"] }
}
```
`terraform_remote_state` 없음 — 결합은 태그 규약으로만 이루어진다.
`live/hub/networking`이 apply되지 않으면 이 조회 결과가 비어서 plan이 명확하게 실패한다(조용한
오작동 아님).

## 크로스 계정 확장 (eks-cluster-v0.8.0)

`enable_argocd_hub_pod_identity`는 이 루트가 **처음으로** 켤 수 있는 변수다 — 허브 ArgoCD가
스포크 계정 EKS에 crossaccount로 접근하는 IAM 전제(`docs/02-choose-your-path.md` 질문 D,
`iac-module-library` `docs/05-modules.md` 「크로스 계정 확장」).

- 지금은 `false`다 — 스포크(`cross-account-trust-role` 모듈)가 아직 없다.
- 스포크가 서고 신뢰 Role ARN이 생기면(notepad 우선순위 4~5번) `argocd_hub_assumable_role_arns`에
  그 ARN을 채우고 `true`로 전환하는 **별도 커밋**을 만든다.
- `argocd_namespace`는 모듈 기본값 `"argocd"`를 그대로 쓴다 — `scripts/argocd-seed.sh`의
  `ARGOCD_NAMESPACE`와 일치해야 한다(모듈 repo 규약).

## Backend 설정

`networking/`과 같은 패턴: `backend.hcl` gitignored, CI에서만 `assume_role`. **버킷은
`live/dev`와 별도**(hub 전용 `s3-demo-hub-an2-tfstate-*`), key는 `hub/eks.tfstate`.

## 의존성

### 내부
- `live/hub/networking/`이 먼저 apply되어야 함(태그로 VPC 조회)

### 외부
- `iac-module-library` eks-cluster 모듈(`v0.8.0`) · workbench 모듈(`v0.6.0`)
- S3 backend + Roles — **`live/dev`와 별도**(`bootstrap/`이 생성, 같은 계정이지만 별도 소유 —
  `bootstrap/README.md` 「5.6」참조). OIDC provider만 AWS 제약으로 dev와 공유한다

## 제약사항

| 제약 | 메커니즘 |
|------|---------|
| **공개 접근 없음** | `endpoint_public_access = false` — apiserver는 VPC 내부에서만 도달(첫 apply부터, 전환 이력 없음) |
| Addon 안정성 | AWS 기본 버전으로 핀, 최신 아님(값은 `main.tf` 참조) |
| 이 루트에서 파기 금지 | 모듈의 `prevent_destroy`(`deletion_protection` 교차변수 validation) |
| `enable_argocd_hub_pod_identity=true` 전제조건 | `argocd_hub_assumable_role_arns`가 비어 있으면 plan 실패(모듈 validation) |

<!-- MANUAL: -->

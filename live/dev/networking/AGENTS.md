<!-- Parent: ../../../AGENTS.md -->
<!-- Generated: 2026-08-04 | Updated: 2026-08-04 -->

# live/dev/networking

## 목적
VPC 배포 루트. Enterprise급 네트워킹 생성: 9개 서브넷 그룹, 20개 서브넷, 3개 라우트 테이블, NAT Gateway, IGW, confused-deputy 방어가 포함된 VPC Flow Logs.

## 주요 파일

| 파일 | 설명 |
|------|------|
| `backend.tf` | **`terraform { backend "s3" {} }` 만** — 버킷 명은 init 시 주입됨 |
| `main.tf` | VPC 모듈 호출 (`vpc-v1.2.0` 태그). naming + env + region_code를 `naming` 객체로 전달 |
| `outputs.tf` | 서브넷 ID, VPC ID, IGW ID — `eks/` 루트가 태그 조회를 통해 소비 |
| `providers.tf` | AWS provider 블록 (alias `aws`). `assume_role` 없음 — CI의 backend.hcl에서 제공 |
| `variables.tf` | 입력 계약: `vpc_enabled`, `deletion_protection`, `flow_logs_enabled`, `naming` |
| `versions.tf` | OpenTofu + provider 버전 제약 |
| `README.md` | pre-apply 체크리스트 (EKS apply 전제 조건) |

## 모듈 소싱

```hcl
source = "git::https://github.com/skax-ca/iac-module-library.git//modules/vpc?ref=vpc-v1.2.0"
```

태그 핀이 **승격 게이트**다. 업그레이드 = `iac-module-library`에 새 태그를 커밋하는 것.

## AI 에이전트 가이드

### init (로컬 전용 — CI는 자체 처리)
```bash
tofu init -backend-config=backend.hcl   # backend.hcl이 반드시 존재해야 함 (gitignored)
tofu plan
tofu apply
```

### Plan / Apply (CI)
```bash
# plan job
tofu init -backend-config=backend.hcl
tofu plan -out=tfplan

# apply job (workflow_dispatch에서만)
tofu apply tfplan   # "tofu apply"(재-plan)禁止 — 다른 plan이 적용됨
```

### Backend 설정 (D25)
`backend.hcl`은 **gitignored**. 내용:
```hcl
bucket = "s3-ref-dev-an2-tfstate-<guid12>"
key    = "dev/networking.tfstate"
region = "ap-northeast-2"
# CI만: assume_role (provider의 assume_role은 backend에 도달하지 않음)
```

### 네이밍 규약 (SSOT = `iac-module-library/docs/reference/aws-naming-abbreviations.md`)
```
vpc-ref-dev-an2-main
igs-ref-dev-an2-main
rtb-ref-dev-an2-main-*
sng-ref-dev-an2-main-*
```

## 의존성

### 내부
- `live/dev/eks/`가 태그 조회를 통해 VPC를 읽음 (remote_state 의존성 없음)

### 외부
- `iac-module-library` vpc 모듈 (`vpc-v1.2.0`)
- S3 backend 버킷 (`bootstrap/`이 생성)
- OIDC provider + 2단 Role 체인 (`bootstrap/`이 생성)

## 적용 이력

| 실행 | 결과 |
|------|------|
| 첫 apply (2026-07-31) | 66개 추가, 0개 변경, 0개 파기 |
| 두 번째 apply (같은 날) | 변경 없음 (ignore_tags 검증됨) |
| v1.2.0 승격 (2026-08-03) | 0개 추가, 20개 변경, 0개 파기 (서브넷 태그 in-place) |
| PR#14 merge (2026-08-04) | 0개 추가, 6개 변경, 0개 파기 (서브넷 태그) |

## 제약사항

| 제약 | 메커니즘 |
|------|---------|
| `prevent_destroy` | D12 교차변수 validation — `deletion_protection=true` + `vpc_enabled=false` 조합에서 plan 실패 |
| `ignore_tags` | `cz-*` 접두사 + `CreationTime` + `Creator` 무시. 자동 태거 태그가 diff를 만들지 않음 |
| 거버넌스 태그 | 100% 루트의 `default_tags`에서 자동 부착. 개별 리소스에 반복하지 않음 |

<!-- MANUAL: -->
<!-- Parent: ../../../AGENTS.md -->
<!-- Generated: 2026-08-19 | Updated: 2026-08-19 -->

# live/hub/networking

## 목적
VPC 배포 허브 루트. `live/dev/networking`을 템플릿으로 복사(2026-08-19, 허브-스포크 크로스 계정
IAM 설계 구현 1단계). Enterprise급 네트워킹: 9개 서브넷 그룹, 20개 서브넷, 3개 라우트 테이블,
NAT Gateway, IGW, confused-deputy 방어가 포함된 VPC Flow Logs — dev와 **동일 구조**, CIDR만 다르다.

## 주요 파일

| 파일 | 설명 |
|------|------|
| `backend.tf` | **`terraform { backend "s3" {} }` 만** — 버킷 명은 init 시 주입됨 |
| `main.tf` | VPC 모듈 호출 (`vpc-v0.3.0` 태그). naming + env + region_code를 `naming` 객체로 전달 |
| `outputs.tf` | 서브넷 ID, VPC ID, IGW ID — `live/hub/eks` 루트가 태그 조회를 통해 소비 |
| `providers.tf` | AWS provider 블록. `assume_role` 없음 — CI의 backend.hcl에서 제공 |
| `variables.tf` | 입력 계약: `env` 기본값 `hub`(dev와 갈리는 지점) |
| `versions.tf` | OpenTofu + provider 버전 제약 |
| `README.md` | 형상·주입 값 설명 |

## 모듈 소싱

정확한 태그 핀은 이 루트의 `main.tf`의 `source`가 유일한 사실(SSOT)이다 — 여기 다시 적지 않는다.

```hcl
source = "git::https://github.com/skax-ca/iac-module-library.git//modules/vpc?ref=<main.tf 참조>"
```

## AI 에이전트 가이드

### Plan / Apply (CI 전용 — 로컬 plan/apply는 성립하지 않는다, D27-1)
```bash
# plan job
tofu init -backend-config=backend.hcl
tofu plan -out=tfplan

# apply job (workflow_dispatch에서만)
tofu apply tfplan   # "tofu apply"(재-plan) 금지 — 다른 plan이 적용됨
```

### Backend 설정 (D25)
`backend.hcl`은 **gitignored**. `live/dev/networking`과 **같은 버킷**, key만 다르다:
```hcl
bucket = "s3-demo-dev-an2-tfstate-<guid12>"   # dev와 공유
key    = "hub/networking.tfstate"              # dev는 dev/networking.tfstate
region = "ap-northeast-2"
```

### 네이밍 규약 (SSOT = `iac-module-library/docs/aws-naming-abbreviations.md`)
```
vpc-demo-hub-an2-main
igs-demo-hub-an2-main
rtb-demo-hub-an2-main-*
sng-demo-hub-an2-main-*
```

## 의존성

### 내부
- `live/hub/eks/`가 태그 조회를 통해 이 VPC를 읽음 (remote_state 의존성 없음)

### 외부
- `iac-module-library` vpc 모듈 (`vpc-v0.3.0`)
- S3 backend 버킷·OIDC provider·2단 Role 체인 — **`live/dev`와 공유**(`bootstrap/`이 생성,
  같은 계정이므로 hub 전용 bootstrap 불필요. 단, 입구 Role 신뢰 정책에는 `environment:hub`
  sub 패턴을 2026-08-19 추가했다 — `bootstrap/config.sh` 참조)

## 제약사항

| 제약 | 메커니즘 |
|------|---------|
| `prevent_destroy` | 교차변수 validation — `deletion_protection=true` + `vpc_enabled=false` 조합에서 plan 실패 |
| `ignore_tags` | `cz-*` 접두사 + `CreationTime` + `Creator` 무시. 자동 태거 태그가 diff를 만들지 않음 |
| 거버넌스 태그 | 100% 루트의 `default_tags`에서 자동 부착. 개별 리소스에 반복하지 않음 |

<!-- MANUAL: -->

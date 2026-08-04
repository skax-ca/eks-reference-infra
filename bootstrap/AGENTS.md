<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-08-04 | Updated: 2026-08-04 -->

# bootstrap

## 목적
IaC 밖 부트스트랩: S3 state 버킷, OIDC provider, 2단 IAM Role 체인을 만든다.
Terraform/OpenTofu가 아니라 일반 `aws` CLI 스크립트다. 의도적인 설계 (D21 — 달걀이 먼저라서 IaC로 부트스트랩할 수 없다).

## 주요 파일

| 파일 | 설명 |
|------|------|
| `bootstrap.sh` | 메인 진입점. 4개 리소스를 멱등하게 생성 |
| `config.sh` | 공유 설정 (태그 값, 환경변수로 계정 ID 주입) |
| `verify.sh` | **읽기 전용** drift 감지. Exit 0=일치, 1=drift, 2=오류 |
| `README.md` | 기대 상태 표 (이것이 SSOT — `.tf` 파일이 아니다) |

## 생성되는 리소스

| 리소스 | 이름 |
|--------|------|
| S3 버킷 (tfstate) | `s3-ref-dev-an2-tfstate-<guid12>` |
| OIDC provider | `token.actions.githubusercontent.com` |
| 입구 Role | `iamr-ref-dev-an2-gha-entry-01` |
| 실행 Role | `iamr-ref-dev-an2-gha-exec-01` |

## AI 에이전트 가이드

### 부트스트랩 실행
```bash
# 로컬 (profile team, backend.hcl에 assume_role 없음)
./bootstrap.sh

# CI (repo 변수로 계정 ID 주입)
EXPECTED_ACCOUNT=123456789012 bash bootstrap.sh
```

### 멱등성 계약
두 번째 실행은 `CHANGES=0`이어야 한다. 이것이 D21 완화책 1의 수용 기준이다.

### 수정하지 말 것
- ⛔ **`AWSAFTExecution` Role** — D27-1. 신뢰 정책이 깨져 있지만 남의 자산이다. 우리 자산이 아니다.
- ⛔ `update-assume-role-policy` 로직을 추가하지 말 것. 이 내용이 `bootstrap.sh`에 나타나면 잘못된 것이다.

### verify.sh 계약
- **읽기 전용** — 절대 리소스를 변경하지 않음
- Exit 0 = drift 없음
- Exit 1 = drift 발견
- Exit 2 = 실행 오류 (예: 환경변수 누락)
- 부정 테스트 검증됨: 잘못된 계정 ID 주입 → exit 2 (exit 1 아님). 스크립트가 실행 오류와 drift를 구분한다.

### Drift 감지 범위
- S3: versioning, SSE, public block, lifecycle
- IAM: 신뢰 정책 principal + 인라인 정책 (정확 일치)
- OIDC: `aud=sts.amazonaws.com`

## 의존성

### 내부
- `config.sh` — 실행 전에 반드시 source해야 함

### 외부
- `aws` CLI (기본 profile: `team`)
- bash 4.x+

## 제약사항

| 제약 | 이유 |
|------|------|
| `--description`에 한글禁止 | IAM description은 Latin-1만 허용. 한글 입력 시 `ValidationError` 발생 |
| Role 생성 후 assume 재시도 로직 | IAM eventual consistency — 방금 만든 Role이 신뢰 정책 principal으로 인정되기까지 수 초 소요 |
| `backend.hcl` 미관여 | Backend 버킷이 bootstrap이 만드는 것이다. 달걀 역전 불가 |

<!-- MANUAL: 2026-08-04 — D27-1 AWSAFTExecution 경고 명시 · 부정 테스트 실측 기록 -->
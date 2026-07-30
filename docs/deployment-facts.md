# 배포 사실 (이 인스턴스 고유)

> **D26**: 소비 **규약**은 `iac-module-library` `docs/design/50-reference-consumer-repo.md`(D-CONSUME)와
> `docs/consumer/*`가 SSOT다. 이 문서는 **그 규약을 이행한 이 인스턴스의 사실**만 기록한다.

> ⚠️ **이 문서는 값이 아니라 포인터를 기록한다.**
> D25는 계정 식별 정보(버킷명·계정 ID·Role ARN)를 git에 남기지 않기로 했다.
> `backend.tf`가 고객사에 복사해 줄 템플릿이기 때문이다. 그 근거를 이 문서에도 적용한다 —
> **"값이 무엇인가"가 아니라 "어디에 있는가"를 적는다.**
> 그렇지 않으면 `backend.tf`에서 뺀 정보가 `docs/`로 새어 나가 D25가 무의미해진다.

---

## 1. git에 적어도 되는 값

노출돼도 AWS 리소스 식별로 이어지지 않는 것들이다.

| 항목 | 값 | 확정 | 용도 |
|------|-----|------|------|
| GitHub org | `skax-ca` | ✅ | — |
| GitHub org 숫자 ID | `310520211` | ✅ 2026-07-30 실측 | OIDC `sub` 조립(D28) |
| 이 repo 숫자 ID | `1316830050` | ✅ 2026-07-30 실측 (생성 `2026-07-30T04:34:22Z`) | OIDC `sub` 조립(D28) |
| 모듈 repo | `skax-ca/iac-module-library` | ✅ | 소싱 대상 |
| 모듈 태그 | `vpc-v1.0.0` | ✅ | 정확 핀 |
| workload code | `ref` (D24) | ✅ | `Name` 태그 2번째 토큰 |
| env | `dev` | ✅ | — |
| region / regioncode | `ap-northeast-2` / `an2` | ✅ | — |
| OIDC 발급자 | `token.actions.githubusercontent.com` | ✅ | provider URL |
| OIDC audience | `sts.amazonaws.com` | ✅ | `aws-actions/configure-aws-credentials` 기본값 |
| 실행 Role **이름** | `AWSAFTExecution` (D27, 기존 재사용) | ✅ | ARN은 §2 |
| 입구 Role **이름** | `iamr-ref-dev-an2-gha-entry-01` | ✅ 설계 확정 | ARN은 §2 |
| state key | `dev/networking.tfstate` | ✅ | backend `key` |

> 이 repo는 **2026-07-15 이후 생성**(2026-07-30)이므로 immutable `sub` 적용 대상으로 추정된다.
> ⚠️ **추정이다.** 실제 형태는 §3에서 실측해 확정한다.

---

## 2. git에 두지 않는 값 — 어디에 있는가

| 항목 | 저장 위치 | 주입 경로 |
|------|----------|----------|
| **state 버킷명** | GitHub repo 변수 `TF_STATE_BUCKET` / 로컬 gitignore된 `backend.hcl` | `tofu init -backend-config="bucket=..."` |
| **AWS 계정 ID** | 입구 Role ARN에 포함 → repo 변수 `AWS_ENTRY_ROLE_ARN` | `configure-aws-credentials`의 `role-to-assume` |
| **입구 Role ARN** | repo 변수 `AWS_ENTRY_ROLE_ARN` | 동일 |
| **실행 Role ARN** | repo 변수 `AWS_EXECUTION_ROLE_ARN` | provider `assume_role.role_arn` |
| **GitHub App private key** | repo **secret** `MODULE_READER_KEY` | `create-github-app-token` |
| **GitHub App ID** | repo 변수 `MODULE_READER_APP_ID` | 동일 |

버킷명 형식은 `s3-ref-dev-an2-tfstate-<guid12>` (D25). **GUID는 `bootstrap.sh`가 생성하고
실행자에게 출력한다** — 이 문서에 적지 않는다.

### 검증
```bash
# 버킷명이 git 어디에도 없는지 (D25 수용 기준)
git grep -c "$TF_STATE_BUCKET" ; # → 0 이어야 한다 (grep 실패 = 없음)
```

---

## 3. 실측 대기 — OIDC `sub` claim (Phase 2)

⚠️ **신뢰 정책을 쓰기 전에 반드시 채운다.** 추정으로 쓰면 `Not authorized to perform
sts:AssumeRoleWithWebIdentity`를 만나고, 그 시점에는 원인이 `aud`인지 `sub`인지 provider ARN인지
구분되지 않는다. **그래서 Phase 2가 Phase 3보다 앞에 있다.**

| job | 트리거 | 예상 `sub` (추정) | 실측값 |
|-----|--------|------------------|--------|
| PR plan | `pull_request` | `repo:skax-ca@310520211/iac-reference-infra@1316830050:pull_request` | ⏸ |
| main plan | `push` → `main` | `...@1316830050:ref:refs/heads/main` | ⏸ |
| apply | `environment: dev` | `...@1316830050:environment:dev` | ⏸ |

측정 방법: `id-token: write` 권한으로 `$ACTIONS_ID_TOKEN_REQUEST_URL`에서 JWT를 받아 payload를
디코드해 출력한다. **AWS 리소스가 전혀 필요 없다** — 그래서 부트스트랩보다 먼저 할 수 있다.

⚠️ 실측 후 throwaway 워크플로는 **삭제**한다(커밋으로).

---

## 4. 부트스트랩 결과 (Phase 3)

`bootstrap/README.md`의 기대 상태 표가 SSOT다. 이 절은 그곳을 가리킨다.

| 리소스 | 이름 | 상태 |
|--------|------|------|
| state 버킷 | `s3-ref-dev-an2-tfstate-<guid12>` (버저닝·SSE·퍼블릭차단·**lifecycle**) | ⏸ |
| OIDC provider | `Name` 태그 `iamoidc-ref-dev-an2-gha` (식별자는 URL) | ⏸ |
| 입구 Role | `iamr-ref-dev-an2-gha-entry-01` | ⏸ |
| 실행 Role | `AWSAFTExecution` — **신뢰 정책 전체 교체**(D27) | ⏸ |

⚠️ **D29**: 버저닝 + `use_lockfile=true`는 lock 객체 버전을 폭증시킨다(OpenTofu 공식 경고).
lifecycle 규칙이 **선택이 아니다**.

⚠️ **D27 알려진 문제**: TFC용 입구 Role이 삭제되어 `AWSAFTExecution`의 신뢰 정책 principal이
unique ID로 치환됐다 → 현재 assume 불가. `update-assume-role-policy`로 전체 교체한다.

---

## 5. apply 판정 결과 (Phase 4~5)

모듈 repo `docs/design/10-vpc-module.md` §3의 apply 미검증 6항목.

| # | 항목 | 판정 시점 | 결과 |
|---|------|----------|------|
| 1 | secondary CIDR `depends_on` 순서 | 후속 시나리오 | ⏸ |
| 2 | primary/secondary 조합 제약 | 후속 시나리오 | ⏸ |
| 3 | CIDR 겹침 | 후속 시나리오 | ⏸ |
| 4 | Flow Logs 실제 배달 | 후속 시나리오 | ⏸ |
| 5 | `prevent_destroy` 실동작 (D12) | 후속 시나리오 | ⏸ |
| 6 | **`git tag` 소싱 경로** | **첫 CI `init`** | ⏸ |
| — | 가짜 diff 없음 (`ignore_tags` 필요 여부) | **두 번째 apply = `No changes`** | ⏸ |

⚠️ **첫 apply로 1~5가 판정되지 않는다.** 흐리면 과잉 주장이다.

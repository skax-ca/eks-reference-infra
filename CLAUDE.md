# CLAUDE.md — 프로젝트 규칙

**레퍼런스 소비 repo.** `iac-module-library`의 모듈을 git tag로 소싱하는 **배포 루트**다.
실 고객사 배포가 아니라 **소비 경로 리허설**이고, 통과한 형태를 고객사 repo로 복사해 준다.

**스택**: OpenTofu(`tofu`) + GitHub Actions(OIDC) + S3 backend(`use_lockfile`)

---

## 0. ⛔ 설계는 이 repo에 없다 (반드시 먼저 읽을 것)

소비 경로 규약의 **SSOT는 모듈 repo**다. 이 repo에서 설계를 새로 만들지 않는다.

| repo | 역할 |
|------|------|
| `iac-module-library` | 모듈·**설계**의 SSOT. `docs/design/50-reference-consumer-repo.md` = **D-CONSUME**(D20~D29) |
| **이 repo** | 그 설계의 **첫 이행 인스턴스**. 배포 루트와 배포 사실만 소유 |
| `terraform-enterprise-poc` | 2026-07-28 **동결**. TFE 제안서 레퍼런스 전용 — 고치지 않는다 |

- **D20~D29를 재논의하지 않는다.** 실측 근거와 기각 이유가 D-CONSUME에 다 있다.
  특히 *"부트스트랩을 IaC로 하면 되지 않나"*(D21) · *"버킷명에 계정 ID를 넣으면 간단한데"*(D25)는
  **이미 값을 매겨 결정한 안**이다.
- 규약을 바꿔야 한다면 **모듈 repo의 D-CONSUME을 고치고** 여기로 내려온다. 역방향은 drift다.
- 설계 변경 없이 구현을 시작하지 않는다: **설계(모듈 repo) → 검토 → 구현(여기) → 검증**.

### D26 — 무엇이 어느 repo에 있나

| 대상 | 위치 |
|------|------|
| 소비 **규약** (소싱 인증·backend 규약·OIDC 체인·plan artifact 규칙) | 모듈 repo `docs/consumer/*` · `docs/design/50` |
| 이 인스턴스의 배포 **사실** | 이 repo `docs/deployment-facts.md` |

---

## 1. 🔑 backend는 부분 설정이다 (D25) — 잊으면 init이 실패한다

`backend.tf`는 **`terraform { backend "s3" {} }` 뿐**이다. **버킷명이 git에 없다.**

| 경로 | 주입 방법 |
|------|----------|
| CI | GitHub repo 변수 → `tofu init -backend-config="bucket=${{ vars.TF_STATE_BUCKET }}" ...` |
| 로컬 | **gitignore된** `backend.hcl` → `tofu init -backend-config=backend.hcl` |

- ⛔ `backend.hcl`을 커밋하지 않는다. `.gitignore` + pre-commit 훅의 별도 검사가 이중으로 막는다.
- 근거: AWS 공식이 **예측 불가능한 버킷명을 권장**하고, 이 repo의 `backend.tf`는
  **고객사에 복사해 줄 템플릿**이라 "private이니 안 보인다"는 논리가 성립하지 않는다(D25).
- **계정 식별 정보 일반으로 확장한다**: 계정 ID·Role ARN도 git에 두지 않고 repo 변수에 둔다.
  D25 근거의 직접적 연장이다. `docs/deployment-facts.md`는 **값이 아니라 포인터**를 기록한다.

---

## 2. 🏷️ 네이밍 & 태깅 (모듈 repo 규약을 그대로 따른다)

```
(resourcetype)-(workloadcode)-(env)-(regioncode)-(purpose)-(serial|suffix)
예) vpc-ref-dev-an2-main · iamr-ref-dev-an2-gha-entry-01 · iamoidc-ref-dev-an2-gha
```

| 토큰 | 이 repo의 값 |
|------|-------------|
| resourcetype | 모듈 repo `docs/reference/aws-naming-abbreviations.md` (**SSOT, 312개, 임의 생성 금지**) |
| workloadcode | **`ref`** (D24) |
| env | `dev` |
| regioncode | `an2` (ap-northeast-2) |

- **약어가 카탈로그에 없으면**: 생략도 임의 생성도 금지. **사용자에게 물어 확정 → 모듈 repo 카탈로그
  등재 → 구현** 순서다. 등재 시 **3곳을 함께 고친다**(섹션 헤더 · 상단 총계 · 끝 카운트 요약표).
- **거버넌스 태그는 루트 `default_tags`로** 100% 자동 부착. 개별 리소스에 반복하지 않는다.
- **`Name`은 모듈이 조합한다.** 루트는 `naming` 객체(`{workload, env, region_code}`)만 넘긴다 —
  소비자가 약어를 타이핑하지 않게 하는 것이 규약의 핵심이다.
- ⚠️ 실제 계정에서는 **`ignore_tags`가 거의 항상 필요하다.** 랜딩존/AFT 자동 태거가 붙인 태그는
  state에 없어 방치하면 전 리소스에 "태그 제거" 가짜 diff가 생긴다.
  판정 기준: **두 번째 `apply`가 `No changes`를 내는가.**

---

## 3. 모듈 소싱 (D20)

```hcl
module "vpc" {
  source = "git::https://github.com/skax-ca/iac-module-library.git//modules/vpc?ref=vpc-v1.0.0"
}
```

- **소싱 URL은 `git::https://` 하나로 유지한다.** 인증은 CI에서만 `git config ... insteadOf`로 주입되고
  코드는 인증 방식을 모른다. SSH URL로 바꾸지 않는다.
- 태그는 **컴포넌트별 semver 정확 핀**. git 소싱에는 `~>`가 동작하지 않는다 —
  업그레이드는 **태그를 올리는 명시적 커밋**이고, 그것이 승격 게이트다.
- ⚠️ `//modules/vpc`는 clone **후** 경로 선택이다. CI는 **repo 전체**를 받는다(실측).

---

## 4. 워크플로 — "승인한 계획 = 적용된 계획"

**한 워크플로 두 job**으로 만족시킨다. 별도 워크플로로 쪼개면 artifact를 run 경계 밖에서 찾아야 하고
**그 조회 지점이 곧 구멍**이다.

| 항목 | 규칙 |
|------|------|
| plan → apply | plan을 **artifact로 저장**해 승인 후 **그 파일을 apply**한다. `tofu apply tfplan` — 재-plan 금지 |
| 승인 게이트 | Environment protection rules(required reviewers). apply job만 `environment:`를 선언한다 |
| 동시 실행 | `concurrency: {group: live-dev-networking, cancel-in-progress: false}` |
| 자격증명 | GitHub OIDC → 입구 Role → 실행 Role(**2단 체인**). 정적 키 금지 |
| state | S3 + `use_lockfile = true` (DynamoDB 불필요) |

- ⚠️ **plan job과 apply job의 `sub`가 다르다**(D28) — `environment:`를 선언한 job만
  `:environment:<name>`을 받는다. 신뢰 정책은 **3패턴**이다.
- ⚠️ **plan artifact는 민감할 수 있다.** 리소스 속성이 평문으로 들어간다 → `retention-days: 1`.
- ⚠️ 역할 체인 세션은 **최대 1시간**(연장 불가). apply job이 다시 인증하므로 승인 지연은 문제없지만,
  그 사이 state가 바뀌면 `apply`가 거부한다 — **정상 동작**이고 재-plan이 필요하다.

---

## 5. 부트스트랩은 IaC 밖이다 (D21) — 완화책이 규약이다

`bootstrap/`은 aws CLI 스크립트다. 닭-달걀이 성립하지 않는 대신 **drift 감지·이력·IaC 자산성을
잃는다.** 그래서 아래 4개는 선택이 아니라 요건이다.

| 요건 | 내용 |
|------|------|
| 멱등성 | 재실행이 안전해야 한다. 이미 원하는 상태면 no-op |
| 기대 상태 명문화 | `bootstrap/README.md`의 표가 `.tf`를 대체하는 SSOT다 |
| drift 감지 대체 | `verify.sh`(**read-only**)가 불일치를 exit 1로 낸다. ⚠️ **음성 테스트로 실제로 잡는지 증명**해야 한다 |
| IaC 승격 경로 | `bootstrap/README.md`에 `import` 블록 초안 |

---

## 6. 검증

### 코드 작성 전
- **리소스 스키마**: 새 리소스/인자 사용 전 `mcp__opentofu__get-resource-docs`로 확인(**추정 금지**).
  인자는 `namespace`·`name`·`resource` 3개이고 **단독 호출된다**.
- **버전 존재 확인**: 핀을 걸기 전에 registry에 그 버전이 있는지 본다 —
  `curl -s https://registry.opentofu.org/v1/providers/<ns>/<name>/versions`
- **스타일**: `.tf` 작성 시 `terraform-style-guide` 스킬 로드.

### 코드 변경 후 (git hook이 강제)
```
tofu fmt -recursive -check → tflint --recursive → trivy config . → tofu validate
```
- clone마다 1회: `git config core.hooksPath .githooks`
- `pre-commit`: **backend.hcl 유출 검사** + fmt·tflint·trivy
- `pre-push`: `live/` 변경 시 각 루트 `init -backend=false` + `validate`
- 우회(`--no-verify`)는 긴급 시에만 — 사유를 커밋 메시지에 명시한다.
- ⚠️ `tofu test`는 없다. 배포 루트는 모듈이 아니다 — 모듈 계약 검증은 모듈 repo가 담당한다.
- ⚠️ tflint `terraform_unused_declarations`는 미사용 변수를 exit 2로 잡는다. 실제 커밋 단위는
  "변수가 전부 소비되는 시점"이다.

---

## 7. 과잉 주장 금지

첫 `apply`가 판정하는 것은 모듈 미검증 6항목 중 **6번(git tag 소싱 경로)과 minimal 경로뿐**이다.
secondary CIDR·CIDR 겹침·Flow Logs 배달·`prevent_destroy`는 **후속 apply 시나리오**다.

이 구분을 흐리면 "apply로 검증했다"는 과잉 주장이 되고, 그것이 모듈 repo
`docs/reference/poc-findings.md`가 경계하는 바로 그 실수다. **실증한 것만 실증했다고 쓴다.**

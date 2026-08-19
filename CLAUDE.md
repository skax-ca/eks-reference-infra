# CLAUDE.md — 프로젝트 규칙

**읽는 사람**: 이 배포 루트에서 코드를 쓰거나 배포 절차를 실행하는 사람.

**레퍼런스 소비 repo.** `iac-module-library`의 모듈을 git tag로 소싱하는 **배포 루트**다.
실 고객사 배포가 아니라 **소비 경로 리허설**이고, 통과한 형태를 고객사 repo로 복사해 준다.

**스택**: OpenTofu(`tofu`) + GitHub Actions(OIDC) + S3 backend(`use_lockfile`)

---

## 0. 설계는 이 repo에 없다 (반드시 먼저 읽을 것)

소비 경로 규약의 **SSOT는 모듈 repo(`iac-module-library`)의 `docs/`**다. 이 repo에서 설계를 새로 만들지 않는다.

| repo | 역할 |
|------|------|
| `iac-module-library` | 모듈·**설계**의 SSOT |
| **이 repo** | 그 설계의 **첫 이행 인스턴스**. 배포 루트와 배포 사실만 소유 |
| `terraform-enterprise-poc` | **동결**. TFE 제안서 레퍼런스 전용 — 고치지 않는다 |

- 아래 각 절의 규칙(부트스트랩을 IaC로 하지 않는 이유·버킷명을 git에 두지 않는 이유·2단 Role
  체인을 쓰는 이유 등)은 전부 **한 번 검토해서 값을 매겨 결정한 것**이다. 재논의하려면 그 절의
  근거를 먼저 반증해야 한다.
- 규약을 바꿔야 한다면 **모듈 repo의 `docs/`를 고치고** 여기로 내려온다. 역방향은 drift다.
- 설계 변경 없이 구현을 시작하지 않는다: **설계(모듈 repo) → 검토 → 구현(여기) → 검증**.
- **이 규칙은 코드 규약에만 그치지 않는다 — 문서 작성 규칙도 같은 SSOT를 따른다.**
  이 repo가 쓰는 모든 문서(`docs/*.md`·`README.md`·`AGENTS.md`·`CLAUDE.md`, `.omc/` 제외)는
  모듈 repo `docs/06-conventions.md`의 「8. 문서 작성 규칙」을 그대로 따른다 — 규칙 텍스트를
  여기 다시 적지 않는다(두 곳에 적으면 갈라진다). 기계 판정 가능한 3개(절 번호 인용 금지·
  비표준 이모지 금지·400줄 제한)는 `scripts/validate-doc-conventions.py`가 pre-commit에서
  강제한다(「6. 검증」 참조). 나머지 4개(첫 줄에 "읽는 사람" 명시·변경 이력 금지·표/명령 우선·
  정정 서술 금지)는 문맥 판단이 필요해 사람이 검토한다.

### 무엇이 어느 repo에 있나

| 대상 | 위치 |
|------|------|
| 소비 **규약**(소싱 인증·backend 규약·OIDC 체인·plan artifact 규칙) | 모듈 repo `docs/` — SSOT |
| **문서 작성 규칙** | 모듈 repo `docs/06-conventions.md`의 「8. 문서 작성 규칙」 — SSOT |
| 이 인스턴스의 배포 **사실** | 이 repo `docs/deployment-facts.md` |

---

## 1. backend는 부분 설정이다 — 잊으면 init이 실패한다

`backend.tf`는 **`terraform { backend "s3" {} }` 뿐**이다. **버킷명이 git에 없다.**

| 경로 | 주입 방법 |
|------|----------|
| CI | repo 변수로 `backend.hcl`을 **runner에서 조립** → `tofu init -backend-config=backend.hcl` |
| 로컬 | **gitignore된** `backend.hcl` → `tofu init -backend-config=backend.hcl` |

- 🔴 **CI의 `backend.hcl`에는 `assume_role`이 들어간다.** backend는 provider와 독립적으로
  자격증명을 해결해서, provider의 `assume_role`이 backend에 적용되지 않는다. 입구 Role의 권한은
  `sts:AssumeRole` 하나뿐이라 걸지 않으면 `init`이 **`HeadObject 403`**으로 죽는다.
  ⚠️ **plan job·apply job 양쪽에 필요하다** — apply job이 `init`을 새로 하기 때문이다.
- ⚠️ `-backend-config=KEY=VALUE` 플래그로는 안 된다. **문자열 값만** 받는데 `assume_role`은 객체다.
- 로컬 `backend.hcl`에는 `assume_role`을 **넣지 않는다** — 개인 IAM user는 실행 Role을
  assume할 수 없고(신뢰가 입구 Role뿐) 버킷은 그 user 권한으로 읽힌다.

- ⛔ `backend.hcl`을 커밋하지 않는다. `.gitignore` + pre-commit 훅의 별도 검사가 이중으로 막는다.
- 근거: AWS 공식이 **예측 불가능한 버킷명을 권장**하고, 이 repo의 `backend.tf`는
  **고객사에 복사해 줄 템플릿**이라 "private이니 안 보인다"는 논리가 성립하지 않는다.
- **계정 식별 정보 일반으로 확장한다**: 계정 ID·Role ARN도 git에 두지 않고 repo 변수에 둔다.
  `docs/deployment-facts.md`는 **값이 아니라 포인터**를 기록한다.

---

## 2. 네이밍 & 태깅 (모듈 repo 규약을 그대로 따른다)

```
(resourcetype)-(workloadcode)-(env)-(regioncode)-(purpose)-(serial|suffix)
예) vpc-demo-dev-an2-main · iamr-demo-dev-an2-gha-entry-01 · iamoidc-demo-dev-an2-gha
```

| 토큰 | 이 repo의 값 |
|------|-------------|
| resourcetype | 모듈 repo `docs/aws-naming-abbreviations.md` (**SSOT, 임의 생성 금지**) |
| workloadcode | **`demo`** |
| env | `dev` |
| regioncode | `an2` (ap-northeast-2) |

- **약어가 카탈로그에 없으면**: 생략도 임의 생성도 금지. **사용자에게 물어 확정 → 모듈 repo 카탈로그
  등재 → 구현** 순서다.
- **거버넌스 태그는 루트 `default_tags`로** 100% 자동 부착. 개별 리소스에 반복하지 않는다.
- **`Name`은 모듈이 조합한다.** 루트는 `naming` 객체(`{workload, env, region_code}`)만 넘긴다 —
  소비자가 약어를 타이핑하지 않게 하는 것이 규약의 핵심이다.
- ⚠️ 실제 계정에서는 **`ignore_tags`가 거의 항상 필요하다.** 랜딩존/AFT 자동 태거가 붙인 태그는
  state에 없어 방치하면 전 리소스에 "태그 제거" 가짜 diff가 생긴다.
  판정 기준: **두 번째 `apply`가 `No changes`를 내는가.**

---

## 3. 모듈 소싱

정확한 태그 핀은 각 배포 루트의 `main.tf`의 `source`가 유일한 사실(SSOT)이다 — 여기 다시 적지 않는다.

```hcl
module "vpc" {
  source = "git::https://github.com/skax-ca/iac-module-library.git//modules/vpc?ref=<live/dev/networking/main.tf 참조>"
}
```

- **소싱 URL은 `git::https://` 하나로 유지한다.** 인증은 CI에서만 `git config ... insteadOf`로 주입되고
  코드는 인증 방식을 모른다. SSH URL로 바꾸지 않는다.
- 태그는 **컴포넌트별 semver 정확 핀**. git 소싱에는 `~>`가 동작하지 않는다 —
  업그레이드는 **태그를 올리는 명시적 커밋**이고, 그것이 승격 게이트다.
- ⚠️ **모듈은 전부 `0.y.z`(개발 단계)다** — 모듈 repo `docs/06-conventions.md`가 SSOT다.
  **이 구간에서는 마이너 업그레이드도 계약을 바꿀 수 있다.** 태그를 올릴 때 `git show <tag>`로
  릴리스 메시지를 읽는다 — 마이너라고 안전을 가정하지 않는다.
- ⚠️ `//modules/vpc`는 clone **후** 경로 선택이다. CI는 **`&depth=1`로 얕게** 받는다(`main.tf`
  소싱 URL 참조) — repo 전체 히스토리는 받지 않는다.

---

## 4. 워크플로 — "승인한 계획 = 적용된 계획"

**한 워크플로 두 job**으로 만족시킨다. 별도 워크플로로 쪼개면 artifact를 run 경계 밖에서 찾아야 하고
**그 조회 지점이 곧 구멍**이다.

**배포 루트마다 워크플로 하나**다 — `deploy-network.yml`(networking) · `deploy-eks.yml`(eks).
경로 필터·state 키·`concurrency` 그룹을 분리해 **두 루트가 서로를 트리거하거나 취소하지 않게** 한다.

| 항목 | 규칙 |
|------|------|
| plan → apply | plan을 **artifact로 저장**해 승인 후 **그 파일을 apply**한다. `tofu apply tfplan` — 재-plan 금지 |
| **트리거** | `push`(main) → **plan까지만** · `workflow_dispatch` → plan + apply. ⛔ `pull_request` 트리거는 **없다** |
| 승인 게이트 | ⚠️ **required reviewers는 이 org(GitHub Free)에서 걸 수 없다**(`docs/deployment-facts.md` 참조) → **dispatch를 누르는 행위가 승인**이다. apply job만 `environment: dev`를 선언한다 |
| 동시 실행 | 루트별로 분리: `live-dev-networking` · `live-dev-eks`. 둘 다 `cancel-in-progress: false` |
| 자격증명 | GitHub OIDC → 입구 Role → 실행 Role(**2단 체인**). 정적 키 금지 |
| state | S3 + `use_lockfile = true` (DynamoDB 불필요). 키는 루트별(`dev/networking.tfstate` · `dev/eks.tfstate`) |

- ⚠️ **잔여 간극**: push run의 plan을 읽고 dispatch하면 dispatch run은 **자기 plan을 새로 만들어**
  적용한다. 그 사이 state가 바뀌면 읽은 것과 적용되는 것이 달라질 수 있다 — run 경계를 넘어 artifact를
  가져오는 것이 더 나쁘므로 이 구조를 택했다. 상위 요금제로 올리면 required reviewers로 승인을
  **같은 run 안**에 넣어 이 간극도 사라진다.
- ⚠️ **plan job과 apply job의 `sub`가 다르다** — `environment:`를 선언한 job만
  `:environment:<name>`을 받는다. 신뢰 정책은 **2패턴**(`ref:refs/heads/main` + `environment:<env>`)이다.
- ⚠️ **plan artifact는 민감할 수 있다.** 리소스 속성이 평문으로 들어간다 → `retention-days: 1`.
- ⚠️ 역할 체인 세션은 **최대 1시간**(연장 불가). apply job이 다시 인증하므로 승인 지연은 문제없지만,
  그 사이 state가 바뀌면 `apply`가 거부한다 — **정상 동작**이고 재-plan이 필요하다.

---

## 4-1. 대상 계정은 **공용 개발 계정**이다 — 가장 먼저 읽을 것

`AWS_PROFILE=team`이 가리키는 계정, 신원은 IAM user다. **계정 ID는 git에 두지 않는다** —
값의 소재는 `docs/deployment-facts.md`가 가리킨다.

**이 계정은 우리 전용이 아니다.** 다수(12명 이상)가 공유하며, VPC·tfstate 버킷 상당수가
다른 사람들 것이다.

| 규칙 | 내용 |
|------|------|
| **남의 자산을 건드리지 않는다** | 우리 자산은 **`Workload=demo` 태그**로 식별한다. 이름만 보고 판단하지 않는다 |
| **`AWSAFTExecution`을 손대지 않는다** | 신뢰 정책이 깨져 있지만 우리는 그 Role을 쓰지 않는다 — 무관하다. 고치는 것도 남의 자산 변경이다 |
| **삭제 대상 사람 검토** | apply 승인 전 plan의 **destroy/replace 목록을 읽는다.** 공용 계정이므로 **예외 없음** |
| **`prevent_destroy` 유지** | VPC 모듈이 건다. 실수 삭제의 마지막 방어선 |
| **`aws` CLI는 항상 `--profile team`** | default 자격증명이 없다. 프로파일을 빼면 실패한다(조용히 다른 계정을 치지 않는다) |

- ⚠️ **`AdministratorAccess`가 자동 트리거에 연결된다.** `push`(main)가 `plan`을 자동 실행한다 —
  실행 Role이 `AdministratorAccess`인 채로 자동 트리거가 걸리는 것이 이 구조의 핵심 위험이다.
- ⚠️ **"사람이 검토"의 이행 지점은 `workflow_dispatch`를 누르는 행위다.** GitHub Free에서는
  required reviewers를 걸 수 없어(`docs/deployment-facts.md` 참조) 승인 게이트가 존재하지 않는다.
  그래서 **merge만으로는 apply되지 않게** 만들었다 — push는 plan까지만 돌고, 그 요약(run Summary
  탭의 destroy/replace 목록)을 읽은 사람이 **Run workflow를 눌러야** apply된다.
- ⚠️ **다른 사람 리소스는 우리 plan에 나타나지 않는다**(우리 state에 없으므로).
  위험은 plan에 잡히는 범위가 아니라 **실행 Role이 손댈 수 있는 범위 전체**다.

---

## 5. 부트스트랩은 IaC 밖이다 — 완화책이 규약이다

`bootstrap/`은 aws CLI 스크립트다. S3 backend·OIDC·IAM Role을 Terraform으로 만들려면 그 Terraform이
먼저 backend에 접근할 자격증명을 가져야 하는데, 그 자격증명이 바로 이 스크립트가 만드는 대상이다
— 닭과 달걀 문제가 성립하지 않는다. 그 대가로 **drift 감지·이력·IaC 자산성을 잃는다.** 그래서
아래 4개는 선택이 아니라 요건이다.

| 요건 | 내용 |
|------|------|
| 멱등성 | 재실행이 안전해야 한다. 이미 원하는 상태면 no-op |
| 기대 상태 명문화 | `bootstrap/README.md`의 표가 `.tf`를 대체하는 SSOT다 |
| drift 감지 대체 | `verify.sh`(**read-only**)가 불일치를 exit 1로 낸다. ⚠️ **음성 테스트로 실제로 잡는지 증명**해야 한다 |
| IaC 승격 경로 | `bootstrap/README.md`에 `import` 블록 초안 |

**생성 대상**

| 리소스 | 이름 | 비고 |
|--------|------|------|
| S3 버킷 | `s3-demo-<env>-an2-tfstate-<hex12>` | 버저닝·SSE·퍼블릭 차단 + **lifecycle** |
| OIDC provider | `token.actions.githubusercontent.com` | `aud`=`sts.amazonaws.com`. `Name` 태그 `iamoidc-demo-an2-gha` |
| **입구** Role | `iamr-demo-<env>-an2-gha-entry-01` | 신뢰=OIDC `sub` 2패턴. 권한=**실행 Role assume 하나뿐** |
| **실행** Role | `iamr-demo-dev-an2-gha-exec-01` | 신뢰=입구 Role만. 권한=`AdministratorAccess` |

⛔ **`AWSAFTExecution`은 생성 대상도 변경 대상도 아니다** — 「4-1. 대상 계정은 공용 개발 계정이다」 참조. `bootstrap.sh`에
`update-assume-role-policy`가 등장하면 안 된다.

---

## 6. 검증

### 코드 작성 전
- **리소스 스키마**: 새 리소스/인자 사용 전 `mcp__opentofu__get-resource-docs`로 확인(**추정 금지**).
  인자는 `namespace`·`name`·`resource` 3개이고 **단독 호출된다**.
- **버전 존재 확인**: 핀을 걸기 전에 registry에 그 버전이 있는지 본다 —
  `curl -s https://registry.opentofu.org/v1/providers/<ns>/<name>/versions`
- **스타일**: `.tf` 작성 시 `terraform-style-guide` 스킬 로드.

### 코드 변경 후 (git hook이 강제)

pre-commit은 **staged 파일 종류에 따라 갈리는 두 갈래**다 — 순서대로 다 도는 단일 체인이 아니다.

| staged | 실행 |
|---|---|
| `docs/*.md`·`README.md`·`AGENTS.md`·`CLAUDE.md` | 문서 작성 규칙 검사(`scripts/validate-doc-conventions.py`) — 모듈 repo `docs/06-conventions.md`의 「8. 문서 작성 규칙」에서 이식(이 문서 「0. 설계는 이 repo에 없다」 참조). 절 번호 인용·비표준 이모지·400줄 초과를 기계로 잡는다 |
| `.tf`·`.tfvars`·`.terraform.lock.hcl`·`.tflint.hcl`·`.trivyignore` | backend.hcl 유출 검사 → `tofu fmt -recursive -check` → `tflint --recursive` → `trivy config .` |

```
pre-push (live/ 변경 시): tofu validate
```
- clone마다 1회: `git config core.hooksPath .githooks`
- 우회(`--no-verify`)는 긴급 시에만 — 사유를 커밋 메시지에 명시한다.
- ⚠️ `tofu test`는 없다. 배포 루트는 모듈이 아니다 — 모듈 계약 검증은 모듈 repo가 담당한다.
- ⚠️ tflint `terraform_unused_declarations`는 미사용 변수를 exit 2로 잡는다. 실제 커밋 단위는
  "변수가 전부 소비되는 시점"이다.

---

## 7. 과잉 주장 금지

**판정표의 SSOT는 `docs/deployment-facts.md`다.** 여기에 복제하지 않는다 — 두 곳에 적으면 갈라진다.

- 배포 루트가 **enterprise 형상**(9그룹·secondary CIDR 2개)이라, minimal 형상 대비 첫 apply의
  판정 범위가 **넓어졌다**. 그렇다고 전부가 판정되는 것은 아니다: **Flow Logs 실제 배달**과
  **`prevent_destroy` 실동작**은 여전히 별도 시나리오다.

**실증한 것만 실증했다고 쓴다.** "apply로 검증했다"는 표현은 실제로 그 항목이 apply 판정 대상이었을
때만 쓴다.

---

## 8. 작업 원칙

대부분 이미 실천하던 것을 규칙으로 승격한 것이다. **이 프로젝트에서 뜻이 달라지는 것은 번역해 뒀다** —
일반 애플리케이션 규칙을 IaC에 그대로 적용하면 틀리는 지점이 있다. *"관심사 분리"·"검증된
라이브러리를 쓴다"*는 여기 적지 않는다 — 모듈 repo가 이미 소유한다(facade 원칙·계층형 하이브리드·
semver 거버넌스). 두 곳에 적으면 갈라진다 — 「7. 과잉 주장 금지」와 같은 이유다.

### 8-1. 발명하기 전에 찾는다

- 해결책을 설계하기 전에 **upstream 모듈·AWS 공식이 그 문제를 이미 어떻게 푸는지** 본다.
  「6. 검증」의 "스키마 추정 금지"는 이 원칙의 한 사례다.
- ⚠️ **"그 기능은 없다"고 단정하지 않는다 — 소스를 열어 확인한다.** facade가 upstream 인자를
  통과시키지 않는 것을, upstream이 그 기능을 지원하지 않는 것으로 오인하면 불필요한 우회를 짜게
  되고 **그 우회가 곧 drift다.** → 확인 경로: `.terraform/modules/` 실물 ·
  `mcp__opentofu__*` · AWS 공식 문서.

### 8-2. 죽은 경로를 남기지 않는다

- 쓰이지 않게 된 코드·스텝·폴백은 **삭제한다.** 호환 레이어를 덧대 두 경로를 유지하지 않는다.
- 🔴 **번역 주의 — "하위 호환을 유지하지 마라"를 계약에 적용하지 않는다.**
  모듈은 **고객사에 배송된다.** 계약 파괴는 숨기는 게 아니라 **semver로 드러내는 것**이 규약이다
  (모듈 repo). 즉 *호환 레이어는 덧대지 않되, 깨는 변경은 메이저로 표시한다.*
- 🔴 **배포된 자산에는 적용되지 않는다.** 태그 이동 같은 "과거를 덮어쓰는" 정리는
  **소비자가 0일 때만** 허용된다. 한 번이라도 apply된 뒤에는 **마이너를 컷한다.**

### 8-3. 지금 요구를 채우는 가장 단순한 형태로 만든다

- 추측에 근거한 추상화·설정값·간접 계층을 만들지 않는다. 필요해지면 그때 연다.
- ⚠️ **안전장치는 "추측 대비"가 아니다.** `prevent_destroy`·`deletion_protection`·교차변수 validation은
  공용 개발 계정(「4-1. 대상 계정은 공용 개발 계정이다」)이라는 **현재 요구사항**이다. 단순화의 이름으로 걷어내지 않는다.

### 8-4. 레이어로 키운다

- 엔드투엔드로 **동작하는 최소**에서 시작해 그 위에 하나씩 얹는다 — networking을 먼저 apply해
  세운 뒤에야 eks를 독립 루트로 얹는 순서가 그 이행이다.
- ⚠️ **IaC에서 "동작한다"의 기준은 `apply`가 통과한 형상이다** — `plan` 통과는 아직 아니다.
- ⛔ 검증되지 않은 층 위에 다음 층을 얹지 않는다. 「7. 과잉 주장 금지」의 다른 얼굴이다.

### 8-5. 임시방편으로 넘기지 않는다

지금만 넘기고 나중에 교체할 우회를 받아들이지 않는다. 규약을 바꿔야 하면
**모듈 repo의 설계를 먼저 고치고 여기로 내려온다** — 「0. 설계는 이 repo에 없다」의 규칙이 이 원칙의 이행 장치다.

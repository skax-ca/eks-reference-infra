# 배포 사실 (이 인스턴스 고유)

> **D26**: 소비 **규약**의 SSOT는 `iac-module-library` `docs/design/50-reference-consumer-repo.md`
> (**D-CONSUME**, D20~D29) **하나**다. 이 문서는 **그 규약을 이행한 이 인스턴스의 사실**만 기록한다.
> ⚠️ 모듈 repo `docs/consumer/*`는 **TFC 시절 잔재**이지 규약이 아니다(D26-1) — 인용하지 않는다.

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
| 실행 Role **이름** | `iamr-ref-dev-an2-gha-exec-01` (**D27-1, 신설**) | ✅ 2026-07-30 생성 | ARN은 §2 |
| 입구 Role **이름** | `iamr-ref-dev-an2-gha-entry-01` | ✅ 2026-07-30 생성 | ARN은 §2 |
| state key | `dev/networking.tfstate` | ✅ | backend `key` |
| GitHub App slug / ID | `skax-ca-module-reader` / `4432001` | ✅ 2026-07-30 실측 | 모듈 소싱 인증(D20) |
| App installation ID | `149998961` | ✅ 2026-07-30 실측 | 토큰 발급 대상 |

> 이 repo는 **2026-07-15 이후 생성**(2026-07-30)이므로 immutable `sub` 적용 대상으로 추정된다.
> ⚠️ **추정이다.** 실제 형태는 §3에서 실측해 확정한다.

### ✅ D20 검증 완료 (2026-07-30) — 미해결 1번 종결

App 토큰만으로 private repo 모듈 소싱이 된다는 것을 **음성 대조군과 함께** 확인했다.

| 확인 항목 | 실측값 |
|-----------|--------|
| App owner | `skax-ca` (**Organization** — 개인 종속 없음, D20의 목적) |
| `repository_selection` | `selected` (전체 설치 아님) |
| 부여된 권한 | `contents: read` + `metadata: read` |
| 토큰으로 접근 가능한 repo | **정확히 1개** — `skax-ca/iac-module-library` |
| installation token | `ghs_` 접두사, 40자, **1시간 만료** |

> ℹ️ **`metadata: read`는 우리가 준 것이 아니다.** GitHub이 모든 App에 자동 부여하는 최소 권한
> (repo 존재·이름 조회용)이다. 권한을 과하게 준 것이 아니므로 보안 리뷰에서 이 줄을 근거로 든다.

**실험 설계 — 음성 대조군이 핵심이다.** 로컬은 `credential.helper=osxkeychain`만으로 이미 clone이
된다(F1). helper를 그대로 두고 App 토큰을 얹어 성공하면 *"App 토큰이 동작했다"* 가 아니라
*"keychain이 동작했다"* 일 수 있다. 그래서 helper를 걷어내고 **먼저 실패하는 것을 확인**했다.

```
격리: GIT_CONFIG_NOSYSTEM=1 · GIT_CONFIG_GLOBAL=<빈 파일> · GIT_TERMINAL_PROMPT=0

① 음성 대조군 (insteadOf 없음)  → fatal: Authentication failed for   ✓ 실패 = 격리 성립
② 본 실험     (App 토큰 insteadOf) → Downloading git::...?ref=vpc-v1.0.0  ✓ 성공
⇒ 성공의 원인이 App 토큰임이 확정된다. 소싱 URL 은 git::https:// 그대로다.
```

⚠️ **`insteadOf` 값에는 토큰이 평문으로 들어간다.** CI에서는 `git config --global`이 runner의
일회용 파일이라 run 종료와 함께 사라지지만, **로컬에서 실험할 때는 반드시 임시 config를 쓰고
끝나면 삭제한다.** 개인 `~/.gitconfig`에 남기면 만료된 토큰이 영구히 박힌다.

---

## 2. git에 두지 않는 값 — 어디에 있는가

**이유가 세 종류다. 섞어 쓰면 판단이 흐려진다.**

| 이유 | 의미 |
|------|------|
| 🔒 **비밀** | 유출 자체가 사고다. GitHub **secret**에만 둔다 |
| 🙈 **비노출** | 비밀은 아니지만 굳이 알릴 이유가 없다(계정 식별 → IAM principal 열거 가능). D25 |
| 🔁 **이식성** | 노출돼도 무해하지만 **고객사가 값만 바꾸면 되게** 하려고 코드 밖에 둔다 |

| 항목 | 이유 | 저장 위치 | 주입 경로 |
|------|------|----------|----------|
| **state 버킷명** | 🙈 | repo 변수 `TF_STATE_BUCKET` / 로컬 gitignore된 `backend.hcl` | `tofu init -backend-config="bucket=..."` |
| **AWS 계정 ID** | 🙈 | 입구 Role ARN에 포함 → repo 변수 `AWS_ENTRY_ROLE_ARN` | `configure-aws-credentials`의 `role-to-assume` |
| **입구 Role ARN** | 🙈 | repo 변수 `AWS_ENTRY_ROLE_ARN` | 동일 |
| **실행 Role ARN** | 🙈 | repo 변수 `AWS_EXEC_ROLE_ARN` | provider `assume_role.role_arn` (`TF_VAR_execution_role_arn` 경유) |
| **GitHub App private key** | 🔒 | repo **secret** `MODULE_READER_KEY` | `create-github-app-token` |
| **GitHub App ID** | 🔁 | repo 변수 `MODULE_READER_APP_ID` | 동일 |

> ℹ️ **App ID(`4432001`)는 비밀이 아니다** — 워크플로 로그에도 찍히고 §1에 값을 적어 두었다.
> 변수로 두는 이유는 **이식성**이다: 고객사는 자기 App을 만들고 변수만 바꾸면 워크플로를 안 고친다.
> 반대로 **private key는 진짜 비밀**이라 secret이고, §1에 값을 적지 않는다.

버킷명 형식은 `s3-ref-dev-an2-tfstate-<guid12>` (D25). **GUID는 `bootstrap.sh`가 생성하고
실행자에게 출력한다** — 이 문서에 적지 않는다.

### 검증
```bash
# 버킷명이 git 어디에도 없는지 (D25 수용 기준)
git grep -c "$TF_STATE_BUCKET" ; # → 0 이어야 한다 (grep 실패 = 없음)
```

---

## 3. ✅ OIDC `sub` claim — 실측 완료 (2026-07-30, Phase 2)

**신뢰 정책에 그대로 넣을 값이다.** 추정이 아니라 실제 JWT를 디코드해 얻었다.

| # | job | 트리거 | **실측 `sub`** |
|---|-----|--------|---------------|
| ① | PR plan (environment 없음) | `pull_request` | `repo:skax-ca@310520211/iac-reference-infra@1316830050:pull_request` |
| ② | main plan (environment 없음) | `push` → `main` | `repo:skax-ca@310520211/iac-reference-infra@1316830050:ref:refs/heads/main` |
| ③ | apply | `environment: dev` | `repo:skax-ca@310520211/iac-reference-infra@1316830050:environment:dev` |

공통: `aud = sts.amazonaws.com` · `iss = https://token.actions.githubusercontent.com`

측정: run [`30524527959`](https://github.com/skax-ca/iac-reference-infra/actions/runs/30524527959)(PR) ·
[`30524983985`](https://github.com/skax-ca/iac-reference-infra/actions/runs/30524983985)(push).
`id-token: write` + `$ACTIONS_ID_TOKEN_REQUEST_URL`에서 JWT를 받아 payload를 디코드했다.
**AWS 리소스가 전혀 필요 없었다** — 그래서 부트스트랩보다 먼저 할 수 있었고, 그것이 Phase 순서의 이유다.

### 확정된 사실 3가지

1. **immutable `sub`가 맞다.** 형태는 `repo:<org>@<org_id>/<repo>@<repo_id>:...`다.
   ⛔ 이름 기반(`repo:skax-ca/iac-reference-infra:...`)으로 썼다면 **세 패턴 전부 불일치**했다.
2. **`environment`를 선언한 job만 environment claim을 받는다.** ③의 claim 키 목록에만
   `environment`·`environment_node_id`가 존재한다 — D28이 claim 스키마 수준에서 확인됐다.
3. ⚠️ **`environment`가 `ref`를 덮어쓴다.** ③은 `ref = refs/heads/main`인데도 `sub`는
   `:environment:dev`다. 따라서 **apply job의 브랜치 제한을 `sub`로 걸 수 없다** —
   필요하면 `token.actions.githubusercontent.com:ref` 조건을 별도로 추가해야 한다.

### 신뢰 정책에 넣을 형태

```json
"StringEquals": { "token.actions.githubusercontent.com:aud": "sts.amazonaws.com" },
"StringLike": {
  "token.actions.githubusercontent.com:sub": [
    "repo:skax-ca@310520211/iac-reference-infra@1316830050:pull_request",
    "repo:skax-ca@310520211/iac-reference-infra@1316830050:ref:refs/heads/main",
    "repo:skax-ca@310520211/iac-reference-infra@1316830050:environment:dev"
  ]
}
```

> ℹ️ 값에 와일드카드가 없으므로 `StringEquals`로도 되지만, 향후 환경·브랜치 추가 시 패턴을 쓰게 되므로
> `StringLike`로 둔다. ⚠️ **`repo:...*` 같은 넓은 와일드카드는 쓰지 않는다** — org 내 다른 repo가
> 이 Role을 assume할 수 있게 된다.

✅ throwaway 워크플로는 측정 후 삭제했다.

---

## 4. ✅ 부트스트랩 결과 — 완료 (2026-07-30, Phase 3)

`bootstrap/README.md` §2의 기대 상태 표가 SSOT다. 이 절은 **그곳을 가리키고 값의 소재만 적는다**.

| 리소스 | 이름 | 값의 소재 | 상태 |
|--------|------|----------|------|
| state 버킷 | `s3-ref-dev-an2-tfstate-<guid12>` (버저닝·SSE·퍼블릭차단·**lifecycle**) | repo 변수 `TF_STATE_BUCKET` / 로컬 `backend.hcl` | ✅ |
| OIDC provider | `Name` 태그 `iamoidc-ref-dev-an2-gha` (식별자는 URL) | 이름이 곧 값 | ✅ |
| **입구** Role | `iamr-ref-dev-an2-gha-entry-01` | ARN은 repo 변수 `AWS_ENTRY_ROLE_ARN` | ✅ |
| **실행** Role | `iamr-ref-dev-an2-gha-exec-01` — **신설**(D27-1) | ARN은 repo 변수 `AWS_EXEC_ROLE_ARN` | ✅ |

> ⚠️ **D27은 철회됐다.** 최초 설계는 `AWSAFTExecution`의 신뢰 정책을 **전체 교체**하는 것이었으나,
> 대상 계정이 공용 개발 계정(§1 F13)임이 실측되어 **D27-1**(실행 Role 신설)로 바뀌었다.
> `AWSAFTExecution`은 **손대지 않았다** — 신뢰 정책이 깨진 채로 남아 있고, 그건 우리 문제가 아니다.

### 검증 (실측)

| 수용 기준 | 결과 |
|-----------|------|
| 멱등성 — 2회차 변경 0건 | ✅ `=== 변경 0건 ===` |
| `verify.sh` exit 0 | ✅ drift 없음 |
| **음성 테스트** — 어긋내면 exit 1 | ✅ S3 버저닝 + IAM inline 정책 2건 주입 → **DRIFT 2건 · exit 1** → `bootstrap.sh`가 **그 2건만** 수정 → exit 0 |
| 부트스트랩 **이전** 상태 감지 | ✅ 6건 전부 `absent`로 잡고 exit 1 |
| **D25** — 버킷명이 git에 없다 | ✅ `git grep -c "<bucket>"` → **0** |

### 이 단계에서 나온 실측 (설계에 없던 것)

1. **IAM은 신뢰 정책 principal의 존재를 검증한다.** "ARN이 결정적이니 계산으로 상호 참조를 끊는다"는
   접근은 동작하지 않는다 → 생성 순서가 **OIDC → 입구 → 실행 → 입구 inline**으로 고정된다.
   (`Resource`는 존재 검증을 받지 않기 때문에 마지막 단계가 가능하다.)
2. **IAM은 eventual consistency다.** 방금 만든 Role이 principal로 인정되기까지 수 초 걸린다 →
   `Invalid principal`일 때만 재시도한다. 없으면 **첫 실행은 반드시 실패**한다.
3. **IAM `--description`은 한글을 거부한다** (tab/LF/CR + U+0020~U+007E + U+00A1~U+00FF만 허용).
4. **OIDC provider의 `--thumbprint-list`는 선택 인자다** (CLI 스키마 실측) → 설정하지 않는다.

⚠️ **D29**: 버저닝 + `use_lockfile=true`는 lock 객체 버전을 폭증시킨다(OpenTofu 공식 경고).
lifecycle 규칙이 **선택이 아니다** — 비현행 7일 · 불완전 MPU 7일로 설정했다.

---

## 5. 배포 루트 `live/dev/networking` — 형상과 CI 제약 (Phase 4)

### 5.1 형상 = enterprise (2026-07-31, 사용자 결정)

모듈 repo `examples/vpc-enterprise`(9그룹 착수 템플릿)를 복사해 이 계정 대역에 맞췄다.
설계 `design/50`이 상정한 것은 minimal(`examples/vpc`)이었으나 **enterprise로 상향**했다.

| CIDR | 성격 | 배치 |
|------|------|------|
| `10.50.0.0/24` primary | uniq 소형 — 인프라 전용 | `ep-uniq` · `tgw-uniq` |
| `10.51.0.0/16` secondary | uniq — 라우팅 가능 | `pub`·`elb`·`vm`·`node`·`db`·`data` |
| `100.64.0.0/16` secondary | dup 허용(RFC 6598) | `pod-dup` |

> 세 대역 모두 **대상 계정에서 미사용임을 실측**하고 골랐다(VPC 23개의 연결 CIDR 전수 조회).
> 겹침이 지금 장애를 만들지는 않지만(peering·TGW 없음), 이 코드는 **고객사에 복사돼 나간다.**

서브넷 20개 · RT 11개 · NAT 1개(`single_nat_gateway`) · IGW 1개 · Flow Logs 1개.
`deletion_protection = true`(D12) — teardown이 2단계가 된다.

### 5.2 ⚠️ 계정 자동 태거 — `ignore_tags`는 추정이 아니라 실측 요건이다

`CLAUDE.md` §2가 *"실제 계정에서는 `ignore_tags`가 거의 항상 필요하다"* 고 경고만 해 뒀던 것의
**실증**이다(2026-07-31).

| 리소스 | 전체 | 자동 태그가 붙은 것 |
|--------|------|-------------------|
| VPC | 23 | **22** (나머지 1개는 태거 도입 전 default VPC) |
| Subnet | 82 | **78** |
| IGW | 17 | **16** |

붙는 키는 생성 주체(CloudFormation·Terraform·콘솔)와 **무관하게 동일**하다:

```
CreationTime · Creator · cz-org · cz-owner · cz-ext1 · cz-ext2 · cz-ext3
```

구세대 6건은 `cz-owner`·`cz-project`·`cz-stage` — 태거가 한 번 개정된 흔적이다.
→ `providers.tf`가 `keys = ["CreationTime","Creator"]` + `key_prefixes = ["cz-"]`로 방어한다.
**판정 기준은 두 번째 apply가 `No changes`를 내는가**이고, 그것만이 이 블록이 맞다는 증거다.

### 5.3 ⚠️ 승인 게이트 — GitHub **Free 플랜**에서 required reviewers를 걸 수 없다

D27-2는 *"apply는 승인 게이트 필수. Environment protection rules"* 를 요구한다.
**이 org에서는 그 요구가 이행되지 않는다.** 규칙별로 하나씩 시험해 경계를 확정했다(2026-07-31).

| protection rule | free + private repo | 응답 |
|-----------------|--------------------|------|
| required reviewers | ❌ | `422 Please ensure the billing plan supports the required reviewers protection rule.` |
| wait timer | ❌ | `422 ... supports the wait timer protection rule.` |
| **deployment branch policy** | ✅ | 적용됨 — rule id `61366642`, 허용 브랜치 `main` 하나 |

`gh api orgs/skax-ca` → `plan.name = "free"` · `filled_seats = 1`.

**채택한 운영 형태(사용자 결정): free 유지 + PR merge를 검토 지점으로.**

```
PR 생성 → plan job 자동 실행 → PR 댓글에 destroy/replace 목록 + plan 전문
       → 사람이 읽고 merge          ← 검토 지점 (강제력 없음)
       → push:main → plan → apply   ← 대기 없이 진행
```

- ✅ 유지되는 것: `environment: dev` 선언(→ `sub` 패턴 ③ 일치) · branch policy(`main`만)
- ❌ 잃는 것: **"읽어야 진행된다"는 강제력.** merge 권한자와 apply 승인자가 분리되지 않고,
  자기 PR을 자기가 merge할 수 있다.
- 완화: `deploy.yml`의 plan job이 `will be destroyed`·`must be replaced`를 **전문 위로 끌어올려**
  PR 댓글과 job summary에 남긴다. 이는 *"읽을 수 있게 한다"* 이지 *"읽어야 진행된다"* 가 아니다.

> ℹ️ **뜻밖의 소득**: 걸린 하나(branch policy)가 하필 §3의 미해결 제약을 메운다.
> `environment`가 `sub`의 `ref`를 덮어써서 **apply job의 브랜치 제한을 `sub`로 걸 수 없었는데**,
> deployment branch policy가 그 자리를 맡는다. IAM에서 표현 불가능한 조건을 GitHub 레이어가
> 대신 거는 구조다.

> ⏭️ **이것은 소비 규약의 문제이지 이 인스턴스의 문제가 아니다** — 모든 소비 repo가 부딪힌다.
> 따라서 **모듈 repo `design/50` 개정(Phase 5)에 D27-2의 전제 조건으로 등재**해야 한다:
> *"승인 게이트는 GitHub Team 이상을 요구한다. Free private repo에서는 이행 불가."*

---

## 6. apply 판정 결과 (Phase 4~5)

모듈 repo `docs/design/10-vpc-module.md` §3의 apply 미검증 6항목.

**⚠️ enterprise 형상(§5.1)을 택한 결과로 판정 시점이 재산정됐다.** minimal 전제로 쓰인
`CLAUDE.md` §7과 `design/50` §4의 *"첫 apply는 6번과 minimal 경로만 판정한다"* 는
**이 배포 루트에는 더 이상 맞지 않는다** — secondary CIDR 2개와 isolated 라우팅이 실제로 만들어진다.

| # | 항목 | 판정 시점 | 왜 | 결과 |
|---|------|----------|-----|------|
| 1 | secondary CIDR `depends_on` 순서 | **첫 apply** | `secondary_cidr_blocks`에 2개를 넘긴다 | ⏸ |
| 2 | primary/secondary 조합 제약 | **첫 apply** | `10.50.0.0/24` + `10.51.0.0/16` + `100.64.0.0/16` 조합을 API가 수락하는지 | ⏸ |
| 3 | CIDR 겹침 | **첫 apply** | 20개 서브넷이 `cidrsubnet()` 파생이다. 겹치면 API가 거부한다 | ⏸ |
| 4 | Flow Logs 실제 **배달** | **첫 apply 이후 별도 확인** | 로그 그룹 생성 ≠ 이벤트 도착. CWL에 실제로 쌓이는지 봐야 한다 | ⏸ |
| 5 | `prevent_destroy` 실동작 (D12) | **teardown 시나리오** | `deletion_protection = true`로 두었으나, 파기를 시도해야 판정된다 | ⏸ |
| 6 | **`git tag` 소싱 경로** | **첫 CI `init`** | 로컬은 이미 통과(F1·아래). CI 경로가 미검증분이다 | ⏸ |
| — | 가짜 diff 없음 (`ignore_tags`) | **두 번째 apply = `No changes`** | §5.2 | ⏸ |

⚠️ **여전히 4·5는 첫 apply가 판정하지 않는다.** 범위가 넓어진 것이지 전부가 된 것이 아니다.
표에 ✅가 찍힌 것만 "실증했다"고 쓴다(`CLAUDE.md` §7).

### 로컬 사전 통과 (2026-07-31, CI 이전)

| 게이트 | 결과 |
|--------|------|
| `tofu init -backend=false` | ✅ 모듈 소싱 성공 — `Downloading git::...?ref=vpc-v1.0.0` · aws **6.57.1**(모듈 repo lock과 동일) |
| `tofu validate` | ✅ Success |
| `tofu fmt -recursive -check` | ✅ 0건 |
| `tflint --recursive` | ✅ exit 0 |
| `trivy config` | ✅ 0건 |

> ⚠️ 이것은 **로컬 경로**다. 미검증 6번(CI git tag 소싱)은 로컬 `osxkeychain`이 자격증명을
> 공급하므로(F1) 여기서 판정되지 않는다. **CI의 첫 `init`만이 6번을 판정한다.**

⚠️ **로컬 `plan`은 성립하지 않는다.** 실행 Role의 신뢰가 입구 Role 하나뿐이라(D27-1) 개인 IAM
user로는 assume되지 않는다. 결함이 아니라 신뢰 경계이며, `live/dev/networking/README.md` §2에 적혀 있다.

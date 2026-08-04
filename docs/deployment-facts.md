# 배포 사실 (이 인스턴스 고유)

> **D26**: 소비 **규약**의 SSOT는 `iac-module-library` `docs/design/50-reference-consumer-repo.md`
> (**D-CONSUME**, D20~D30) **하나**다. 이 문서는 **그 규약을 이행한 이 인스턴스의 사실**만 기록한다.
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
| **GitHub App Client ID** | 🔁 | repo 변수 `MODULE_READER_CLIENT_ID` | `create-github-app-token`의 `client-id` |

> ℹ️ **Client ID(`Iv23…`)는 비밀이 아니다** — public `/apps/{slug}` 엔드포인트로 조회되고 워크플로
> 로그에도 찍힌다. 변수로 두는 이유는 **이식성**이다: 고객사는 자기 App을 만들고 변수만 바꾸면
> 워크플로를 안 고친다. 반대로 **private key는 진짜 비밀**이라 secret이고, §1에 값을 적지 않는다.
> 🔁 **`app-id` → `client-id` 전환(2026-07-31)**: `create-github-app-token@v3.2.0`이 `app-id`를
> legacy로 경고한다(동작은 유지). Client ID로 옮기며 변수도 `MODULE_READER_APP_ID`(숫자 `4432001`)에서
> `MODULE_READER_CLIENT_ID`로 교체했다. 숫자 App ID는 client-id와 **다른 값**이다.

버킷명 형식은 `s3-ref-dev-an2-tfstate-<guid12>` (D25). **GUID는 `bootstrap.sh`가 생성하고
실행자에게 출력한다** — 이 문서에 적지 않는다.

### 검증
```bash
# 버킷명이 git 어디에도 없는지 (D25 수용 기준)
git grep -c "$TF_STATE_BUCKET" ; # → 0 이어야 한다 (grep 실패 = 없음)
git grep -l "<계정 ID>"          # 아래 예외 2건 외에는 없어야 한다
```

### ✅ 계정 ID 정리 완료 (2026-07-31)

D25의 연장은 *"계정 ID·Role ARN도 git에 두지 않는다"* 인데, Phase 1·3의 산출물에 2건이 남아
있었다. 두 repo를 전수 조사해 **모두 정리했다.**

| 위치 | 처리 | 비고 |
|------|------|------|
| `bootstrap/config.sh` | **환경변수 필수 주입**으로 전환 | 아래 |
| `CLAUDE.md` §4-1 | 값 제거 → *"프로파일이 가리키는 계정"* + 이 문서 포인터 | 동료 리소스 prefix 목록도 함께 제거 |
| 모듈 repo `design/50` F6·F13·F14 | 값 → 서술·포인터 | 규약 SSOT는 고객사에 인용되므로 더 무겁게 봤다 |
| 모듈 repo `docs/consumer/dynamic-credentials.md` | 12곳 → `<poc-account-id>` | 절차 기록의 가치는 ARN의 *형태*이지 *값*이 아니다 |

#### `EXPECTED_ACCOUNT` — 왜 "그냥 지우기"가 안 됐나

앞선 판단(*"안전장치라 값이 코드에 있어야 기능한다"*)은 **절반만 맞았다.** 안전장치는 값을
**비교**할 뿐이라 밖에서 받아도 되지만, `oidc_arn()`·`role_arn()`은 값을 **소비**한다 —
지우면 부트스트랩 전체가 죽는다.

→ **기본값 없는 환경변수**로 바꿨다. 안전장치·ARN 조립·D25가 동시에 만족되고, 부수 효과로
실행자가 **어느 계정에 도는지 매번 명시**하게 된다. 공용 계정(F13)에서는 그 자체가 방어다.

```bash
EXPECTED_ACCOUNT=<12자리> bash bootstrap/bootstrap.sh
```

⛔ *"해시로 저장해 비교하면 되지 않나"* 는 **이미 기각된 안**이다(D25) — 계정 ID 공간이 10¹²뿐이라
전수 해싱이 가능하다. **해시가 보호가 되지 않는다.** 남는 해법은 "값을 밖에서 받는다" 하나다.

#### 검증 (실측)

| 경우 | exit | 계약 |
|------|------|------|
| 미설정 | **2** | 실행 불가 |
| 형식 오류(11자리) | **2** | 실행 불가 |
| 계정 불일치 | **2** | 실행 불가 |
| 정상 | **0** | 일치 — drift 0건(10항목 전부 `ok`) |

> 🔑 **`: "${VAR:?msg}"`를 쓰면 안 됐다.** bash 기본 **exit 1**을 내는데 `verify.sh`의 계약은
> `0=일치 / 1=drift / 2=실행 불가`다. 미설정은 drift가 아니라 실행 불가이므로 2여야 한다 —
> 그대로 뒀다면 **CI가 "drift 있음"으로 오판**했을 것이다. 명시적 체크 + `exit 2`로 고쳤다.

⚠️ 이 문서를 쓰면서도 한 번 새게 했다 — §5.5 참조. **발견을 서술할 때가 가장 위험하다.**

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
- 완화: plan job이 `will be destroyed`·`must be replaced`를 **전문 위로 끌어올려** 남긴다.
  이는 *"읽을 수 있게 한다"* 이지 *"읽어야 진행된다"* 가 아니다.
  > 🔄 **2026-08-03 갱신(D30-1)**: 위 문장의 "PR 댓글"은 더 이상 없다 — `pull_request` 트리거를
  > 제거하면서 댓글 step 도 함께 사라졌다. 요약은 **run 의 Summary 탭**에만 남는다. 대신 **apply 가
  > `workflow_dispatch` 전용**이 되어, 그 요약을 읽고 **버튼을 누르는 행위**가 승인 자리를 대신한다 —
  > "읽을 수 있게 한다"에서 **"누군가 의도적으로 실행해야 한다"**로 한 칸 올라갔다(강제력은 여전히 없다).
  > 파일명도 배포 루트별로 갈렸다: `deploy-network.yml` · `deploy-eks.yml`.

> ℹ️ **뜻밖의 소득**: 걸린 하나(branch policy)가 하필 §3의 미해결 제약을 메운다.
> `environment`가 `sub`의 `ref`를 덮어써서 **apply job의 브랜치 제한을 `sub`로 걸 수 없었는데**,
> deployment branch policy가 그 자리를 맡는다. IAM에서 표현 불가능한 조건을 GitHub 레이어가
> 대신 거는 구조다.

> ⏭️ **이것은 소비 규약의 문제이지 이 인스턴스의 문제가 아니다** — 모든 소비 repo가 부딪힌다.
> 따라서 **모듈 repo `design/50` 개정(Phase 5)에 D27-2의 전제 조건으로 등재**해야 한다:
> *"승인 게이트는 GitHub Team 이상을 요구한다. Free private repo에서는 이행 불가."*

### 5.4 🔴 **backend는 provider의 `assume_role`을 쓰지 않는다** — 설계 §3의 빈틈

**첫 CI plan이 여기서 실패했다** (run [`30592702396`](https://github.com/skax-ca/iac-reference-infra/actions/runs/30592702396), 2026-07-31).

```
Successfully configured the backend "s3"!
Error: Error refreshing state
  operation error S3: HeadObject, https response error StatusCode: 403
  api error Forbidden: Forbidden
```

**원인.** `design/50` §3의 2단 체인 그림은 *"configure-aws-credentials → 입구 Role →
**provider의 `assume_role`** → 실행 Role"* 이다. 그런데 **S3 backend는 provider가 아니다.**
OpenTofu 공식 문서가 backend 자격증명은 provider 설정과 **독립적으로** 해결된다고 명시한다.

따라서 backend는 환경 자격증명(= 입구 Role)으로 S3에 붙는데, 입구 Role의 권한은 실측상
`sts:AssumeRole` **하나뿐**이다(D27-1의 의도된 최소권한):

```json
{ "Effect": "Allow", "Action": "sts:AssumeRole",
  "Resource": "arn:aws:iam::…:role/iamr-ref-dev-an2-gha-exec-01" }
```

→ S3를 읽을 권한이 없다. **설계대로 만들었기 때문에 실패했다.**

**선택한 해법: backend에도 같은 실행 Role을 체인 assume 시킨다.**

```hcl
# CI 가 repo 변수로 조립하는 backend.hcl (gitignore 대상 이름이라 커밋될 수 없다)
bucket       = "…"
key          = "dev/networking.tfstate"
region       = "ap-northeast-2"
use_lockfile = true
assume_role = {
  role_arn     = "…/iamr-ref-dev-an2-gha-exec-01"
  session_name = "tofu-backend-<run_id>"
}
```

- 기각한 대안: **입구 Role에 S3 권한을 추가한다.** *"입구 Role의 권한은 실행 Role assume
  하나뿐"* 이라는 D27-1의 신뢰 경계가 깨진다. 입구 Role은 OIDC로 직접 도달 가능한 지점이라
  거기에 권한을 얹으면 2단 체인의 의미가 줄어든다.
- ⚠️ **`-backend-config=KEY=VALUE`로는 표현할 수 없다** — 문자열 값만 받는데 `assume_role`은
  객체다. 그래서 CI도 **HCL 파일**을 조립해 넘긴다(로컬 규약과 형태가 같아지는 부수 효과).

**스키마 확인**(추정하지 않았다): 로컬에서 `assume_role` 블록을 넣고 `init`을 돌려 파싱 오류가
아니라 `STS AssumeRole 403 AccessDenied`가 나는 것을 확인했다 — backend가 그 객체를 읽고 실제로
assume을 시도했다는 뜻이다. 동시에 **개인 IAM user는 실행 Role을 assume할 수 없다**는
`live/dev/networking/README.md` §2의 서술도 실증됐다.

> ⏭️ **이것도 소비 규약의 문제다.** `design/50` §3의 2단 체인 그림에 **backend 경로가 빠져 있다.**
> Phase 5에서 고친다 — 모든 소비 repo가 첫 CI run에서 똑같이 부딪힌다.

### 5.5 ⚠️ repo 변수는 CI 로그에 **평문**으로 남는다

같은 run의 로그에서 확인했다 — `-backend-config="bucket=<실제 버킷명>"`이 **그대로 찍혀 있었다.**

> ⚠️ **이 문서에는 그 로그를 인용하지 않는다.** 초안에서 실제로 인용했다가 되돌렸다 —
> "값이 로그에 남는다"를 지적하면서 그 값을 git에 옮겨 적으면 D25를 그 자리에서 위반한다.
> **§2의 원칙(값이 아니라 포인터)은 발견을 서술할 때도 예외가 없다.**

GitHub은 **secret만 마스킹**한다. repo 변수(`vars.*`)는 마스킹 대상이 아니다.
§2에서 버킷명·Role ARN을 "🙈 비노출"로 분류하고 repo 변수에 둔 것은 **git 에 남기지 않기**
위해서였고(코드가 고객사로 복사되므로), 그 목적 자체는 유지된다. 그러나
**"어디에도 평문으로 없다"는 아니다** — repo read 권한자는 워크플로 로그에서 볼 수 있다.

- 현재 판단: private repo이고 plan artifact(`retention-days: 1`)와 노출 대상이 같으므로 수용한다.
- 완화하려면 첫 스텝에서 `::add-mask::`를 쓰거나 값을 secret으로 옮긴다. ⚠️ `add-mask` 스텝
  **자신의** 명령·env echo에는 값이 찍히므로 완전하지 않다.
- **열린 항목으로 등재한다** — `design/50` §5의 "plan artifact 암호화"와 같은 성격의 미해결이다.

---

## 6. apply 판정 결과 (Phase 4~5)

모듈 repo `docs/design/10-vpc-module.md` §3의 apply 미검증 6항목.

**⚠️ enterprise 형상(§5.1)을 택한 결과로 판정 시점이 재산정됐다.** minimal 전제로 쓰인
`CLAUDE.md` §7과 `design/50` §4의 *"첫 apply는 6번과 minimal 경로만 판정한다"* 는
**이 배포 루트에는 더 이상 맞지 않는다** — secondary CIDR 2개와 isolated 라우팅이 실제로 만들어진다.

| # | 항목 | 판정 시점 | 결과 | 증거 |
|---|------|----------|------|------|
| 1 | secondary CIDR `depends_on` 순서 | 첫 apply | ✅ | `describe-vpcs` → `10.50.0.0/24`·`10.51.0.0/16`·`100.64.0.0/16` 3개 모두 `associated` |
| 2 | primary/secondary 조합 제약 | 첫 apply | ✅ | 위 조합을 API가 수락했다. primary가 `10.0.0.0/15` 밖이라 성립 |
| 3 | CIDR 겹침 | 첫 apply | ✅ | `cidrsubnet()` 파생 서브넷 **20개** 전부 생성. 겹쳤다면 API가 거부한다 |
| 4 | Flow Logs 실제 **배달** | 첫 apply 이후 | ✅ | 스트림 `eni-…-all`에 실제 레코드: `2 <account> eni-… → 10.51.32.63 … ACCEPT OK` (목적지가 `pub-uniq-a` 대역 = NAT ENI) |
| 5 | `prevent_destroy` 실동작 (D12) | **teardown 시나리오** | ✅¹ | `vpc_enabled = false` PR([#9](https://github.com/skax-ca/iac-reference-infra/pull/9)) → CI **plan job이 D12 validation으로 거부**: `deletion_protection = true인 상태에서는 vpc_enabled = false로 파기할 수 없다`. apply skip, 자산 그대로. PR은 merge 없이 닫음 |
| 6 | **`git tag` 소싱 경로** | 첫 CI `init` | ✅ | `Downloading git::…iac-module-library.git?ref=vpc-v1.0.0` — App 토큰 + `insteadOf` |
| — | 가짜 diff 없음 (`ignore_tags`) | 두 번째 apply | ✅ | `No changes.` → `Apply complete! Resources: 0 added, 0 changed, 0 destroyed.` |

**¹ 5번 판정 범위 — §7 정직성**: 라이브로 판정된 것은 D12의 **교차변수 validation** 가드다
(`vpc_enabled = false` while `deletion_protection = true` → plan 거부). 이것이 이 모듈의 실제
teardown 시도(D10 kill switch)가 부딪히는 가드이자 "실수 삭제의 마지막 방어선"(§4-1)이다.
D12의 **다른 절반인 `prevent_destroy` lifecycle 메타 인자**(`prevent_destroy = var.deletion_protection`,
`tofu destroy`·replace를 막는다)는 라이브 plan에 존재하고(`= true`) 모듈 계약 테스트
`reject_teardown_while_protected`가 증명하지만, **destroy-plan을 별도로 라이브 실행하진 않았다**
— deploy.yml에 destroy 경로가 없고(스코프 밖), 사용자가 자산 유지를 택했다. 두 가드를 뭉뚱그리지 않는다.

✅가 찍힌 것만 "실증했다"고 쓴다(`CLAUDE.md` §7). **미검증 6항목이 모두 판정됐다.**

### 실행 기록

| run | 트리거 | 결과 |
|-----|--------|------|
| [`30592702396`](https://github.com/skax-ca/iac-reference-infra/actions/runs/30592702396) | PR plan | ❌ backend 403 — §5.4의 발견 |
| [`30592915255`](https://github.com/skax-ca/iac-reference-infra/actions/runs/30592915255) | PR plan | ✅ `Plan: 66 to add, 0 to change, 0 to destroy` |
| [`30593495627`](https://github.com/skax-ca/iac-reference-infra/actions/runs/30593495627) | push→main | ✅ **`Apply complete! Resources: 66 added, 0 changed, 0 destroyed.`** |
| [`30593853991`](https://github.com/skax-ca/iac-reference-infra/actions/runs/30593853991) | push→main | ✅ **두 번째 apply — `No changes` · `0 added, 0 changed, 0 destroyed`** |
| [`30604797319`](https://github.com/skax-ca/iac-reference-infra/actions/runs/30604797319) | push→main | ✅ vpc-v1.1.0 승격 apply — `0 added, 1 changed, 0 destroyed`(Flow Logs 역할 confused deputy 조건, IAM in-place) |
| [`30605752914`](https://github.com/skax-ca/iac-reference-infra/actions/runs/30605752914) | PR plan | ✅**판정** 6-1 — plan이 D12 validation으로 **거부**(파기 시도 차단), apply skip |

### 계정 실측 (2026-07-31, apply 후)

| 대상 | 값 |
|------|-----|
| VPC | `vpc-ref-dev-an2-main` (ID는 계정 식별로 이어지므로 여기 적지 않는다) |
| 연결 CIDR | `10.50.0.0/24` · `10.51.0.0/16` · `100.64.0.0/16` |
| Subnet / Route Table / NAT / IGW | 20 / **12**(우리 11 + VPC 기본 RT 1) / 1 / 1 |
| Flow Logs | `/aws/vpc/flow-log/ref-dev-an2-main` — `ACTIVE`, 레코드 도착 확인 |
| 우리 VPC의 자동 태거 키 | `CreationTime`·`Creator`·`cz-org`·`cz-owner`·`cz-ext1~3` — **7개가 실제로 붙었다** |

> ⚠️ RT가 12인 것은 오류가 아니다. AWS가 VPC 생성 시 **기본 RT 1개**를 자동으로 만든다.
> 우리 state에는 11개만 있고, 나머지 1개는 우리 것이 아니므로 plan에 나타나지 않는다.

### 3개의 인증 경로가 한 run 안에서 전부 동작했다

| 경로 | 무엇을 증명하나 |
|------|----------------|
| GitHub App 토큰 → `insteadOf` → `git::https://` | private repo 모듈 소싱(D20)이 **CI에서** 동작한다 |
| OIDC → 입구 Role | Phase 2에서 실측한 `sub` 패턴이 신뢰 정책과 **실제로** 맞았다 |
| 입구 Role → 실행 Role (**provider + backend 양쪽**) | 2단 체인(D27-1). backend가 별도 경로라는 것이 §5.4의 발견이다 |

### 로컬 사전 통과 (2026-07-31, CI 이전)

| 게이트 | 결과 |
|--------|------|
| `tofu init -backend=false` | ✅ 모듈 소싱 성공 — aws **6.57.1**(모듈 repo lock과 동일) |
| `tofu validate` | ✅ Success |
| `tofu fmt -recursive -check` | ✅ 0건 |
| `tflint --recursive` | ✅ exit 0 |
| `trivy config` | ✅ 0건 |

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

---

## 7. ✅ 미결 항목 #1 해결 — plan/apply 권한 분리

### 결론: 구조 유지, 문서화

**결론은 "변경 없음"이다.** plan job과 apply job을 분리하지 않고, 현재 구조를 그대로 유지하되
권한 실상을 문서화한다.

### 현재 구조

```
plan job  (environment: 없음)   apply job  (environment: dev)
  └─ OIDC: 입구 → 실행 Role       └─ OIDC: 입구 → 실행 Role
  └─ tofu plan -out=tfplan        └─ tofu apply tfplan
  └─ 실행 Role 권한: Admin         └─ 실행 Role 권한: Admin
```

두 job 모두 **동일한 실행 Role(`iamr-ref-dev-an2-gha-exec-01`, `AdministratorAccess`)을 assume**한다.

plan job이 `environment:`를 선언하지 않는 이유는 OIDC `sub`가 `:ref:` 패턴이어야 하기 때문이다 —
§3의 3가지 확정 사실 3번: "`environment`가 `ref`를 덮어쓴다."
apply job의 `environment: dev`는 `sub`를 `:environment:dev`로 바꾸는 동시에
GitHub의 deployment branch policy를 트리거한다.

### 왜 구조를 바꾸지 않는가

| 안 | 내용 | 기각 이유 |
|----|------|----------|
| plan job용 읽기 전용 Role 분리 | plan job만 assume하는 권한 제한 Role(예: `ReadOnlyAccess`) | 실행 Role의 2단 체인을 plan용으로 중복 구성하면 CI 설정 복잡도 ↑ + IAM 리소스 증가. plan job의 `permissions` 자체는 이미 최소(`id-token: write`, `contents: read`) |
| DynamoDB로 lock을 명시화 | DynamoDB table을 만들어 `use_lockfile` 없이 lock 충돌 감지 | S3 + `use_lockfile = true`로 이미 lock 동작 중. DynamoDB는 추가 비용 + provisioning |
| plan job을 제거하고 apply만 두기 | plan과 apply를 하나의 job으로 합침 | `tofu apply`(재-plan)가 승인한 것과 다른 것을 적용한다 — "승인한 계획 ≠ 적용된 계획" 구멍. `tofu apply tfplan`이 이 repo의 약속이다 |

### 왜 이것이 문제가 되는가

**`tofu plan`은 state lock을 잡는다.** 동시 실행 시 plan job이 lock을 획득하면 apply job은 대기한다.
plan이 끝나야 lock이 해제되고 apply가 진행된다. 이는 **잠금 방식 자체가 아니라 lock의 존재**가
관심 대상이다 — 두 job 모두 실행 Role을 assume하므로 plan job이 악성 행위를 할 수 있는 상태가 된다.

그러나 이 문제의 실제 위험은 **이 구조가 선택的结果이 아니라 이식성의 결과**라는 점이다.
이 repo의 소비 규약(모듈 repo `design/50` D-CONSUME)은 plan job과 apply job을 **같은 워크플로,
같은 run**에 두도록 요구한다:

> ⛔ 한 워크플로 두 job을 유지한다(design/50 §3). 별도 워크플로로 쪼개면 plan artifact를
> run 경계 밖에서 찾아야 하고, 그 조회 지점이 곧 "승인한 계획 ≠ 적용된 계획" 구멍이다.
> 같은 run 안이면 `needs:`가 그 관계를 구조적으로 보장한다.

plan job의 `AdministratorAccess`는 그 선택의 결과일 뿐 아니라, 두 job이 같은 자격증명 경로를
거치는 것이 설계의 일부라는 뜻이다.

### 현재 구조가 수용되는 이유

| 조건 | 상태 |
|------|------|
| plan job의 `permissions` | `id-token: write` + `contents: read` — 최소한 |
| terraform 코드 실행 여부 | plan이 state를 직접 수정하지는 않는다 — lock만 잡고 해제 |
| credential 이동 | job 간 자격증명 이동 없음 — 각 job이 독립적으로 인증 |
| artifact scope | plan artifact는 **같은 run 안에서만** apply job이 소비 — run 경계 밖 유출 없음 |
| artifact 수명 | `retention-days: 1` — plan 파일이 오래 남지 않음 |

plan job이 실행 Role(`AdministratorAccess`)을 가지는 것은 "plan = read-only"가 아니라
"이 구조에서는 plan과 apply가 같은 Role을 쓰되, artifact 경계로 승인이라는 보장을 삼는다"는 것이다.

### 작성 기준

This entry resolves 미결 항목 #1 as documented in `.omc/notepad.md`:
> plan/apply 권한 분리 — `tofu plan`도 state lock을 잡아 "plan은 read-only"가 성립하지 않는다(D28)

**결론 (결론 = 변경 없):** C안(현재 구조 유지 + 문서화)을 채택한다.
이것은 결함 수정이 아니라 권한 실상의 명시적 문서화다.
향후 상위 요금제로 전환하면 `environment: dev`에 required reviewers를 걸어 같은 run 안에서 승인을
구현할 수 있고, 그때도 plan/apply job 분리는 유지된다.

---

## 8. ✅ 미결 항목 #4 해결 — CI `init` shallow clone (`&depth=1`)

### 결론: `&depth=1` 파라미터 추가

모듈 소싱 URL에 `&depth=1`을 붙여 불필요한 히스토리 전송을 제거했다.

```hcl
# 변경 전 (전체 히스토리 clone)
source = "git::https://github.com/skax-ca/iac-module-library.git//modules/vpc?ref=vpc-v1.2.0"

# 변경 후 (shallow clone, 태그 기반 핀만 가능)
source = "git::https://github.com/skax-ca/iac-module-library.git//modules/vpc?ref=vpc-v1.2.0&depth=1"
```

### 변경 파일

```
live/dev/networking/main.tf  — vpc 소싱 URL에 &depth=1 추가
live/dev/eks/main.tf         — eks-cluster 소싱 URL에 &depth=1 추가
```

### 왜 되는가 (OpenTofu 공식 문서 실측)

OpenTofu 문서(`opentofu.org/docs/language/modules/sources/#shallow-clone`)에서 확인:

> "The `depth` URL argument corresponds to the `--depth` argument to `git clone`, telling Git to
> create a shallow clone with the history truncated to only the specified number of commits."

**동작 조건:**
- `ref`에 **태그 이름**을 지정해야 함 — 커밋 ID만으로는 동작하지 않음
- 깊이 1이면 가장 최근 커밋만 가져온다
- OpenTofu는 shallow clone에서 모듈 소스 디렉토리만 추출하므로 전체 히스토리가 불필요

**우리 상황:**
- 현재 핀: `vpc-v1.2.0` (태그) ✅, `eks-cluster-v1.0.0` (태그) ✅
- 둘 다 태그 기반이므로 shallow clone이 정상 동작

### 왜 지금 하는가

| 상황 | 이전 | 지금 |
|------|------|------|
| 모듈 repo 크기 | 수십 MB | 수용 가능 |
| 커밋 수 | 수백 개 | 수용 가능 |
| **이후** | 태그/히스토리 증가 | CI 속도 ↑ + 네트워크 비용 + runner 디스크 초과 |
| 해법 비용 | — | URL에 `&depth=1` 한 줄 추가 |

규칙: **불필요한 최적화보다 필요할 때 하는 최적화가 낫다** (§8-3). 지금 모듈 repo 크기가 작을 때
미리 해두면 해법의 동작 여부를 검증할 수 있다 — 이미 있는 태그 기반 핀으로 shallow clone이
정상 동작하는지 **첫 CI run으로 확인할 수 있다.**

### ⚠️ 업그레이드 시 주의

모듈 태그를 올릴 때(승격) `ref=vpc-v1.X.X`의 태그가 유효한지 확인해야 한다.
이것은 이미 정확 핀 규약의 일부다 — 태그를 올리는 것이 곧 승격 커밋이고,
그 커밋이 유효한지는 CI의 `tofu init`이 검증한다.

---

## 9. Future Work

| # | 항목 | 상태 | 참고 |
|---|------|------|------|
| 2 | plan artifact 암호화 | 미해결 | `retention-days: 1`은 완화책 · repo 변수 평문 로그와 같은 계열 |
| 3 | deepinit 실행 | 미해결 | `.tf` 분석 대상이 이제 존재함 — 실행 시점 결정 필요 |

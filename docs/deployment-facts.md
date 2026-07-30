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
| 실행 Role **이름** | `AWSAFTExecution` (D27, 기존 재사용) | ✅ | ARN은 §2 |
| 입구 Role **이름** | `iamr-ref-dev-an2-gha-entry-01` | ✅ 설계 확정 | ARN은 §2 |
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
| **실행 Role ARN** | 🙈 | repo 변수 `AWS_EXECUTION_ROLE_ARN` | provider `assume_role.role_arn` |
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

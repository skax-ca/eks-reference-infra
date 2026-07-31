# Notepad — iac-reference-infra

## 📍 지금 어디인가 (2026-07-31 기준)

```
✅1 골격+App소싱  ✅2 OIDC sub  ✅3 bootstrap  ✅4 apply(66개 생성)  ✅5 design/50 개정
                       ✅6-2 계정정보 정리  ✅MCP(opentofu·aws-docs·aws-api)  ✅6-3 confused deputy
                                    ⏸6-1 prevent_destroy  ← 유일하게 남음(선행 결정 필요)
```

**⏸ 다음 작업 = 6-1 (`prevent_destroy` 판정).** 미검증 6항목 중 **유일하게 남은 것**.
teardown을 시도해야 판정된다 — ⚠️ **파기하면 NAT 월 ~$43이 멈춘다.** 리허설 자산을 계속 둘지가
**선행 결정**이라 자동 진행 금지. 이 파일 아래 「6-1」 절 참조.

⚠️ **MCP 서버 3종이 `.mcp.json`에 있다**(opentofu·aws-docs·**aws-api**). aws-api는 2026-07-31
추가분 — 재시작 후 첫 사용 시 승인 프롬프트. `mcp__opentofu__get-resource-docs`로 스키마 확인이
`CLAUDE.md` §6 요구. 실계정 조회(로그·describe)는 aws-api(**read-only**)로 하되, 없으면 `aws --profile team` CLI.

💰 **비용이 돌고 있다**: `live/dev/networking` 66개 리소스 · NAT 1개(월 ~$43) + Flow Logs.

---

## Priority Context

**레퍼런스 소비 repo** — 2026-07-30 신설. `skax-ca/iac-reference-infra`(private, Team `iac`/maintain).
`iac-module-library`의 모듈을 **git tag로 소싱**하는 배포 루트. 실 고객사 배포가 아니라
**소비 경로 리허설**이고, 통과한 형태를 고객사 repo로 복사해 준다.

### ⛔ 설계는 이 repo에 없다

| repo | 역할 |
|------|------|
| `iac-module-library` | 모듈·**설계** SSOT. `docs/design/50-reference-consumer-repo.md` = **D-CONSUME**(D20~D29) |
| **이 repo** | D-CONSUME의 첫 이행 인스턴스. 배포 루트 + 배포 사실만 소유(D26) |
| `terraform-enterprise-poc` | 2026-07-28 **동결**. 고치지 않는다 |

- **D20~D29를 재논의하지 말 것.** 실측 근거와 기각 이유가 D-CONSUME에 다 있다. 특히
  *"부트스트랩을 IaC로"*(D21) · *"버킷명에 계정 ID를"*(D25)는 **이미 값을 매겨 기각**했다.
- 규약 변경은 **모듈 repo D-CONSUME을 고치고** 여기로 내려온다. 역방향은 drift.

### 🔑 절대 잊지 말 것 — backend는 부분 설정이다 (D25)

`backend.tf`는 **`terraform { backend "s3" {} }` 뿐**. **버킷명이 git에 없다.**
- CI: repo 변수 `TF_STATE_BUCKET` / 로컬: **gitignore된** `backend.hcl`
- `tofu init -backend-config=backend.hcl` 없이는 init이 실패한다 (버그가 아니다)
- pre-commit 훅 1단계가 `backend.hcl` staged 여부를 검사한다 — `--no-verify`로 뚫지 말 것
- **계정 ID·Role ARN도 git에 두지 않는다** (D25 근거의 연장, 커밋 `cfb575a`에서 확정).
  `docs/deployment-facts.md`는 **값이 아니라 포인터**를 기록한다.

### ✅ Phase 1 완료분 (2026-07-30, 커밋 `cfb575a`)

- repo 생성 + Team `iac` `maintain` 연결 ✅
- **repo 숫자 ID = `1316830050`** (생성 `2026-07-30T04:34:22Z`) · org ID = `310520211`
- 골격: `.gitignore`·`.tflint.hcl`(aws 0.48.0 = 모듈 repo와 동일 핀)·`.trivyignore`·
  `.githooks/{pre-commit,pre-push}`·`README.md`·`CLAUDE.md`·`AGENTS.md`·`docs/deployment-facts.md`
- 게이트 실측: `tflint --recursive` 0 · `tofu fmt -check` 0 · `trivy config` 0 ·
  훅 실행 비트 `100755` 확인(**chmod 누락을 실제로 잡았다** — 누락 시 훅이 조용히 안 돈다)
- `git config core.hooksPath .githooks` 활성화됨

### ✅ Phase 1 **완료** — GitHub App + D20 실측 검증 (2026-07-30)

**미해결 1번(private repo git tag 소싱 인증) 종결.** 상세는 `docs/deployment-facts.md` §1.

| 실측값 | 값 |
|--------|-----|
| App slug / ID | `skax-ca-module-reader` / `4432001` (owner=`skax-ca` **Organization** → 개인 종속 없음) |
| installation ID | `149998961` · `repository_selection=selected` |
| 권한 | `contents: read` + `metadata: read` (**metadata는 GitHub이 자동 부여** — 과다 권한 아님) |
| 접근 가능 repo | **정확히 1개** `skax-ca/iac-module-library` |
| 토큰 | `ghs_` 접두사 40자, **1시간 만료** |
| repo 변수/시크릿 | `MODULE_READER_APP_ID`(변수) · `MODULE_READER_KEY`(secret) 등록됨 |

**실험 설계 — 음성 대조군이 핵심이었다.** 로컬은 `osxkeychain`만으로 이미 clone된다(F1).
helper를 그대로 두면 "App 토큰이 동작했다"를 증명할 수 없어, 걷어내고 **먼저 실패를 확인**했다.
```
격리: GIT_CONFIG_NOSYSTEM=1 · GIT_CONFIG_GLOBAL=<빈 파일> · GIT_TERMINAL_PROMPT=0
① insteadOf 없음  → fatal: Authentication failed for   ✓ 실패 = 격리 성립
② App 토큰        → Downloading git::...?ref=vpc-v1.0.0  ✓ 성공
```
⚠️ **`insteadOf` 값에는 토큰이 평문으로 들어간다.** 로컬 실험은 임시 config를 쓰고 지운다 —
`~/.gitconfig`에 남기면 만료 토큰이 영구히 박힌다.

⚠️ **App 생성은 API로 불가**(실측): `POST /orgs/{org}/apps` 없음, manifest 변환은 브라우저 `code` 필요.
고객사 인수인계 문서에 **브라우저 수동 단계**로 명기해야 한다.
⚠️ **App 생성 ≠ 설치.** 처음에 `GET /app`은 200인데 `GET /app/installations`가 **빈 배열**이었다 —
App은 정의, Installation이 적용이다. 설치 없이는 토큰 발급 대상이 없다.
설치 대상은 소싱**당하는** repo(`iac-module-library`)다. `iac-reference-infra`가 아니다.

### ✅ Phase 2 **완료** — OIDC `sub` 3패턴 실측 (2026-07-30, 커밋 `0cc0ec0`+`a2416d9`)

**미해결 3번 종결.** 신뢰 정책에 그대로 넣을 값을 확보했다. 전문은 `docs/deployment-facts.md` §3.

| # | job | **실측 `sub`** |
|---|-----|---------------|
| ① | PR plan (env 없음) | `repo:skax-ca@310520211/iac-reference-infra@1316830050:pull_request` |
| ② | main plan (env 없음) | `repo:skax-ca@310520211/iac-reference-infra@1316830050:ref:refs/heads/main` |
| ③ | apply (`environment: dev`) | `repo:skax-ca@310520211/iac-reference-infra@1316830050:environment:dev` |

`aud = sts.amazonaws.com` · `iss = https://token.actions.githubusercontent.com`
run [`30524527959`](https://github.com/skax-ca/iac-reference-infra/actions/runs/30524527959)(PR) ·
[`30524983985`](https://github.com/skax-ca/iac-reference-infra/actions/runs/30524983985)(push). 워크플로는 삭제됨.

**확정 사실 3가지**
1. **immutable `sub`가 맞다** — `repo:<org>@<org_id>/<repo>@<repo_id>:...`.
   ⛔ 이름 기반으로 썼다면 **세 패턴 전부 불일치**했다.
2. `environment`를 선언한 job만 `environment`·`environment_node_id` claim을 받는다(스키마 수준 확인).
3. ⚠️ **`environment`가 `ref`를 덮어쓴다.** ③은 `ref=refs/heads/main`인데 `sub`는 `:environment:dev`다
   → **apply job의 브랜치 제한을 `sub`로 걸 수 없다.** 필요하면 `...:ref` 조건을 별도로 추가한다.
   **설계 때 예상하지 못한 제약이다.**

⛔ 신뢰 정책에 `repo:...*` 같은 넓은 와일드카드를 쓰지 말 것 — org 내 다른 repo가 assume하게 된다.

### 🧯 이번 세션에서 한 오판 2건 (같은 실수 반복 방지)

1. **run이 안 보인다고 "Actions 비활성화"로 결론냈다.** 실제로는 폴링(07:51~07:53)을
   run 생성(07:54:09) **전에 끝낸 것**이었다. org 정책까지 뒤지고 `admin:org` 스코프를 추가했는데
   불필요했다. billing usage의 "Actions 1분"이 오판을 잡은 단서였다.
   → **run 목록이 비었을 때 충분히 기다린다.** GitHub의 run 생성에는 수십 초 지연이 있다.
2. **`git add A B`는 A가 없으면 B도 스테이징되지 않는다.** `git rm`이 디렉토리를 없애
   `touch`가 실패했고 문서가 커밋에서 누락됐다(`0cc0ec0` → `a2416d9`로 보정).
   → **커밋 후 `git status`가 clean인지 확인한다.**

### ✅ Phase 3 완료 (2026-07-30, 커밋 `d2393a1`)

```
✅3 bootstrap → ⏭️4 live/dev/networking + apply → 5 모듈 repo docs/design/50 개정
```

**⚠️ 대상 계정은 공용 개발 계정이다**(F13, `CLAUDE.md` §4-1). VPC 23개·tfstate 버킷 7개가
남의 것이다. **`Workload=ref` 태그로만 우리 자산을 판별한다.**

**⛔ D27 철회 → D27-1**: `AWSAFTExecution`을 **건드리지 않고** 실행 Role을 신설했다.
전체 교체(`update-assume-role-policy`)는 공용 계정에서 남의 파이프라인을 말없이 끊는다.
실측 확인: `AWSAFTExecution` principal은 **삭제된 주체의 unique ID로 치환된 채 그대로**다.
(⚠️ 값은 적지 않는다 — 남의 자산 식별자다. notepad는 커밋된다.)

생성물 — 값은 **repo 변수에만**(D25 확장, git에 없음):
`s3-ref-dev-an2-tfstate-<guid12>` · OIDC provider · `iamr-ref-dev-an2-gha-entry-01`(입구) ·
`iamr-ref-dev-an2-gha-exec-01`(실행, Admin)

수용 기준 전부 실측 통과: 멱등(2회차 0건) · 음성 테스트(S3+IAM 2건 주입→exit 1→그 2건만 수정) ·
사전 감지(6건 absent) · D25(`git grep` → 0).

**🔑 구현에서 나온 실측 4건** (`docs/deployment-facts.md` §4 · `bootstrap/README.md` §3):
1. **IAM은 신뢰 정책 principal의 존재를 검증한다** — "ARN이 결정적이니 계산으로 상호 참조를
   끊는다"는 접근은 **반증됐다**. 순서가 `OIDC → 입구 → 실행 → 입구 inline`으로 **고정**된다.
   (`Resource`는 존재 검증을 안 받아 마지막 단계가 가능하다.)
2. **IAM eventual consistency** — 방금 만든 Role이 principal로 인정되기까지 수 초.
   재시도 없으면 **첫 실행은 반드시 실패**한다 → 멱등성이 실패를 가려주는 상태(수렴이 아니라 운).
3. IAM `--description`은 **한글 거부**(Latin-1 범위만).
4. OIDC `--thumbprint-list`는 **선택 인자** → 설정하지 않는다(만료 부채 회피).

### ✅ Phase 4 완료 (2026-07-31) — **첫 apply 성공, 미검증 6항목 중 5개 판정**

`live/dev/networking/` + `deploy.yml`(한 run 두 job). PR #2 → apply → PR #3 → 두 번째 apply.

| run | 결과 |
|-----|------|
| `30592702396` PR plan | ❌ backend 403 — **설계의 빈틈 발견**(아래 1번) |
| `30592915255` PR plan | ✅ `Plan: 66 to add, 0 to change, 0 to destroy` |
| `30593495627` push | ✅ **`Apply complete! Resources: 66 added, 0 changed, 0 destroyed.`** |
| `30593853991` push | ✅ **두 번째 apply — `No changes` · `0/0/0`** ← `ignore_tags` 판정 |

**형상 = enterprise**(사용자 결정, 설계는 minimal 상정). 9그룹·서브넷 20·RT 11·NAT 1·IGW 1·FlowLogs.
CIDR은 계정 VPC 23개의 연결 대역을 전수 조회해 빈 곳을 골랐다:
`10.50.0.0/24`(primary) · `10.51.0.0/16` · `100.64.0.0/16`.

**판정표 SSOT = `docs/deployment-facts.md` §6.** ✅ 1·2·3·4·6 + `ignore_tags`. **⏸ 5번(`prevent_destroy`)만 남았다** — teardown을 시도해야 판정된다.

#### 🔑 Phase 4에서 나온 실측 4건 (전부 `docs/deployment-facts.md` §5)

1. **🔴 backend는 provider의 `assume_role`을 쓰지 않는다** (§5.4). `design/50` §3의 2단 체인 그림에
   **backend 경로가 빠져 있다.** backend는 provider와 독립적으로 자격증명을 해결하므로(공식)
   입구 Role 그대로 S3를 쳐서 403이 났다 — 입구 Role 권한은 `sts:AssumeRole` 하나뿐(D27-1).
   → `backend.hcl`에 `assume_role`을 넣어 CI가 매 job 조립한다. `-backend-config=K=V`는
   **문자열만** 받아서 객체인 `assume_role`을 못 넘긴다 → **파일이 유일한 경로**.
   ⛔ 기각: 입구 Role에 S3 권한 추가 — D27-1의 신뢰 경계가 깨진다.
2. **자동 태거가 실제로 돈다** (§5.2). VPC 22/23 · Subnet 78/82 · IGW 16/17에
   `CreationTime`·`Creator`·`cz-org`·`cz-owner`·`cz-ext1~3`이 **생성 주체와 무관하게** 붙는다.
   우리 VPC에도 apply 직후 7개가 붙었고, `ignore_tags`(keys 2 + prefix `cz-`)로 **가짜 diff 0건**.
3. **승인 게이트는 GitHub Free에서 불가** (§5.3). required reviewers·wait timer 둘 다 422(billing).
   **branch policy만 걸린다** → 채택: free 유지 + **PR merge가 검토 지점**(강제력 없음).
   뜻밖의 소득: branch policy가 Phase 2의 구멍(`environment`가 `sub`의 `ref`를 덮어써서
   브랜치 제한 불가)을 메운다.
4. **repo 변수는 CI 로그에 평문으로 남는다** (§5.5). secret만 마스킹된다.

#### ⚠️ 이번 세션의 오판 1건

**"repo 변수가 로그에 평문으로 남는다"를 문서화하면서 그 로그를 인용해 버킷명을 git에 넣었다.**
D25를 지적하는 문장이 D25를 위반했다. → **발견을 서술할 때가 가장 위험하다.**
(계정 ID 2곳도 그때 등재만 했고, **아래 Phase 6-2에서 전부 해소했다.**)

### ✅ Phase 5 완료 (2026-07-31) — 모듈 repo `design/50`·`design/10` 개정

모듈 repo PR [#1](https://github.com/skax-ca/iac-module-library/pull/1) merge 완료(`dec37a9`).

**🆕 D30 신설 — backend도 실행 Role을 체인 assume한다.**
D-CONSUME 범위가 **D20~D30**으로 늘었다(범위 참조 4곳 함께 갱신).
기각안 2개 기록: ① 입구 Role에 S3 권한 추가(D27-1 신뢰 경계가 깨진다)
② role chaining으로 환경 자격증명을 실행 Role로(입구 Role이 "OIDC 유일 도달점"이라는 성질이 흐려진다 → 열린 항목 11).

**F16~F19 추가** · **D27-2에 "승인 게이트는 GitHub Team 이상 요구" 전제 등재** ·
**§4 판정 범위를 형상 의존으로 재서술**(minimal vs enterprise 표) ·
**§0에 "넷째 구간(backend)이 있었다"** 기록 — 셋을 예상했고 넷째에 걸렸다.

`design/10` §3: 미검증 6항목 중 **5개 판정 반영**. 열린 항목 7(Flow Logs confused deputy)의
차단 조건 해소 — 도입 시 수용 기준은 "조건을 넣고 **로그 도착을 재확인**"이다(`apply` 성공은 증거가 아니다).

**등재만 하고 안 고친 것 — 열린 항목 12**: `design/50` F6·F13이 **계정 ID를 노출**한다.
D25 연장·D26 둘 다와 어긋나지만 단순 삭제하면 실측 provenance를 잃는다.
`docs/consumer/*`의 12곳과 함께 판단할 사안이다.

---

## Phase 6 — 3항목 (사용자가 "1,2,3을 차례대로" 지시, 순서는 2 → 3 → 1)

### ✅ 6-2 계정 정보 정리 **완료** (2026-07-31)

모듈 [PR#2](https://github.com/skax-ca/iac-module-library/pull/2)(`f19049a`) · 소비 [PR#6](https://github.com/skax-ca/iac-reference-infra/pull/6)(`98c7310`).
**두 repo `git grep` 기준 계정ID·개인식별자·버킷명 전부 0건.**

전수 조사 16건이 4가지로 갈렸다 → A `bootstrap/config.sh`(1) · B 소비 `CLAUDE.md`(1) ·
C 모듈 `design/50` F6/F13/F14(1) · D 모듈 `docs/consumer/dynamic-credentials.md`(13).

- **A가 핵심.** 이전 판단("안전장치라 코드에 있어야 한다")은 **절반만 맞았다** — 안전장치는
  값을 *비교*할 뿐이고, 진짜 이유는 `oidc_arn()`·`role_arn()`이 값을 ***소비***한다는 것이었다.
  → **기본값 없는 환경변수**로 전환: `EXPECTED_ACCOUNT=<12자리> bash bootstrap/bootstrap.sh`
- 🔑 **`: "${VAR:?msg}"`를 쓰면 안 된다.** bash 기본 **exit 1**인데 `verify.sh` 계약은
  `0=일치 / 1=drift / 2=실행불가`다 → **CI가 "drift 있음"으로 오판**한다. 초안이 실제로 그랬고
  명시적 체크 + `exit 2`로 고쳤다. 실측: 미설정·형식오류·계정불일치 전부 exit 2, 정상 exit 0.
- ⛔ **"해시로 비교하면 되지 않나"는 D25가 이미 기각**했다 — 10¹² 공간은 전수 해싱 가능.
- 동료 리소스 prefix 10개 + 남의 Role unique principal ID도 함께 제거(**개인 식별 정보**에 가깝다).
- D는 `<poc-account-id>` 치환 → **D20 기각안의 "public 전환 선결 과제"가 해소**됐다.
- 🔑 **오탐 2종은 손대지 않았다**: `955636489371`(lock SHA256 substring) ·
  `111122223333`(AWS 공식 예제 ID, `tofu test` mock — 올바른 관행).
- 🔑 **검증은 `grep -rn`이 아니라 `git grep`으로 한다.** grep이 파일 하나를 조용히 놓쳤다
  (python `rglob`은 찾음). 신경 쓸 범위가 정확히 "git이 추적하는 것"이다.

### ✅ MCP 구성 완료 (2026-07-31, [PR#7](https://github.com/skax-ca/iac-reference-infra/pull/7) `984dc11`)

모듈 repo의 `.mcp.json`을 그대로 복사(`diff` 0) — `opentofu`(0.1.5) · `aws-docs`(1.1.28).
**`CLAUDE.md` §6이 `mcp__opentofu__get-resource-docs`를 요구하는데 서버가 없었다.** Phase 4에서
실제로 비용을 냈다(s3 backend `assume_role` 스키마를 WebFetch+로컬 init으로 우회).
⚠️ `.mcp.json`은 **커밋되는 팀 공유 설정**이라 고객사 복사본에 따라간다 — 사내 CA 경로는 고쳐야 한다.
ℹ️ **적용은 Claude Code 재시작 후**, 첫 사용 시 승인 프롬프트.

**➕ aws-api 추가 (2026-07-31)** — 실계정 조회용(`awslabs.aws-api-mcp-server`, PyPI v1.4.1).
- 🔒 **`READ_OPERATIONS_ONLY=true`** — 공용 계정(§4-1)에서 MCP를 통한 우발적 변경 원천 차단.
  우리의 실제 변경은 전부 IaC→CI(OIDC→Role) 경로다. MCP는 조회 전용.
- 🔒 **`AWS_API_MCP_PROFILE_NAME=team`** — §4-1의 "항상 `--profile team`"을 MCP에 강제.
  빼면 boto3가 ambient 자격증명으로 **조용히 다른 계정**을 칠 수 있다.
- **CA 번들 env는 넣지 않았다** — `aws` CLI가 `AWS_CA_BUNDLE` 없이 동작 = AWS 엔드포인트 MITM 아님.
  사내 CA만 담긴 번들을 걸면 오히려 public AWS TLS가 깨진다.
- ⚠️ **모듈 repo `.mcp.json`과 의도적으로 다르다**(PR#7 parity에서 벗어남). aws-api는 **배포 검증
  도구**라 소싱만 하는 모듈 repo엔 불필요하다. "parity 복원"으로 지우지 말 것.
- ⚠️ 고객사 복사 시 `AWS_API_MCP_PROFILE_NAME`은 그들의 프로파일로 바꿔야 한다(버킷명·CA와 동급).

### ✅ 6-3 Flow Logs confused deputy 방어 **완료·검증됨** (2026-07-31)

모듈 [PR#3](https://github.com/skax-ca/iac-module-library/pull/3)(`vpc-v1.1.0`) + [PR#4](https://github.com/skax-ca/iac-module-library/pull/4)(열린 항목 7 닫음) ·
소비 [PR#8](https://github.com/skax-ca/iac-reference-infra/pull/8)(`daf7c63`).

**무엇을 고쳤나**: `modules/vpc/flow-logs.tf` 신뢰 정책에 `Condition` 추가. `vpc-flow-logs.amazonaws.com`은
전 세계 공용 서비스 principal이라, 조건이 없으면 남이 자기 VPC flow log에 우리 Role ARN을 지정해
**남의 트래픽이 우리 로그 그룹으로 들어오고 ingestion 비용이 우리에게 청구**된다(피해 방향이 반대).
```json
"Condition": {
  "StringEquals": { "aws:SourceAccount": "<account>" },
  "ArnLike":      { "aws:SourceArn": "arn:<partition>:ec2:<region>:<account>:vpc-flow-log/*" }
}
```
`data.aws_caller_identity/aws_partition/aws_region` 3개 추가 — **게이트는 `local.flow_logs_enabled`**
(role의 `count`와 일치. 방침 초안의 `local.enabled`보다 정확 — flow logs가 꺼지면 STS 호출도 사라진다).

**🔑 구현에서 나온 실측 3건**
1. **`aws_region.name`·`id`는 provider 6.x에서 deprecated → `region` 속성**(MCP `get-datasource-docs`로
   확인). `.name`으로 썼으면 deprecation 경고 — `CLAUDE.md` §6 "스키마 추정 금지"가 실제로 막은 함정.
2. **와일드카드가 불가피**하다 — flow log ID를 넣으면 Role ↔ flow log 순환 참조로 plan이 실패한다.
   AWS 공식이 `vpc-flow-log/*`를 허용. 계정·리전·서비스 구간이 남아 차단은 성립.
3. **`mock_provider`에서 data source의 computed 속성은 plan 시점에 known**(생성됨) — resource의
   arn·id가 unknown인 것과 다르다. 덕분에 `assume_role_policy`가 완전히 known이 되어 `tofu test`가
   조건의 **존재**를 `jsondecode`로 검사할 수 있다(신규 run 추가).

**판정 (실계정 — 사용자 결정)**: apply `0 added, 1 changed, 0 destroyed`(IAM **in-place**, destroy/replace 0).
apply 완료 시각(epoch ms) 이후로 `aws logs filter-log-events --start-time`가 `ACCEPT OK` 레코드를 돌려줬다
→ 읽힌다 = CloudWatch 배달 성공 = 서비스가 **새 조건 하에서 role assume 성공**. `describe-flow-logs`
`DeliverLogsStatus=SUCCESS` 일치. **조용한 실패였다면 apply 이후 레코드가 비어야 했다 — 음성 근거 확보.**
⚠️ 계정 ID는 plan 출력·flow log 레코드에 평문으로 나타난다(불가피). **git·notepad에는 적지 않는다**(§5.5).

**⚠️ 오판 없이 진행한 지점 하나**: `tofu test`(mock)는 조건의 **존재**만 잠근다 — **배달을 막지 않는지**는
증명 못 한다. 그래서 실계정 로그 도착을 별도 수용 기준으로 잡았고, `apply` 성공에 만족하지 않았다.

### ⏸ 6-1 `prevent_destroy` 판정 — 미착수 (마지막)

미검증 6항목 중 **유일하게 남은 것**. `deletion_protection = true`로 걸어 두고 apply까지 갔으나
**"보호가 설정됐다"이지 "동작한다"가 아니다** — 파기를 시도해야 판정된다.
teardown 2단계: `deletion_protection = false` apply → `vpc_enabled = false` apply.
⚠️ **파기하면 NAT 월 ~$43이 멈춘다** — 리허설 자산을 계속 둘지가 **선행 결정**이라 자동 진행 금지.

---

## 💰 현재 진행 중 비용

`live/dev/networking` 66개 리소스가 살아 있다. NAT Gateway 1개(월 ~$43) + Flow Logs CloudWatch.

### ⚠️ 과잉 주장 금지

판정표 SSOT는 `docs/deployment-facts.md` §6. **✅가 찍힌 것만 실증했다고 쓴다.**
⏸ **5번 `prevent_destroy`는 판정되지 않았다** — `deletion_protection = true`로 걸어 두었을 뿐,
파기를 시도해야 판정된다. teardown은 2단계다(`deletion_protection=false` → `vpc_enabled=false`).

## 미결 항목

- plan/apply 권한 분리 — `tofu plan`도 state lock을 잡아 "plan은 read-only"가 성립하지 않는다(D28)
- CI `init`이 모듈 repo **전체를 clone**한다(실측). 태그·히스토리 증가 시 `?depth=1` 검토
- plan artifact 암호화 — `retention-days: 1`은 완화이지 해결이 아니다
- deepinit은 **Phase 4 이후**에 돌린다 — 지금은 `.tf`가 없어 분석 대상이 없다

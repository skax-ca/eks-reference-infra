# Notepad — iac-reference-infra

## 🔢 현행 모듈 핀 (2026-08-10 기준) — **먼저 읽을 것**

**`vpc-v0.3.0` · `eks-cluster-v0.4.0` · `workbench-v0.4.0`.**

> ### 🔴 **`workbench-v0.4.0` — apply 하면 인스턴스가 교체된다** (2026-08-10)
>
> `v0.1.0` → `v0.3.0` 은 `user_data` 가 바뀌므로 **`forces replacement`** 다. 모듈이
> `user_data_replace_on_change = true` 로 **의도한 계약**이다 — user_data 는 부팅 시에만 실행되므로
> in-place 갱신은 *"코드와 실물이 다른"* 상태를 만든다.
>
> | 유지 | 소실 |
> |---|---|
> | IAM role·instance profile ⇒ **Access Entry(2층) 그대로** | 2026-08-07 seed 때 **손으로 넣은 것 전부** |
> | SG ID ⇒ **cluster SG ingress(3층) 그대로** | `git` · `helm` · `argocd-seed.sh` |
> | kubeconfig — `user_data` 가 재생성 | ⇒ **셋 다 자동으로 돌아온다**(아래) |
>
> - `git` = **`workbench-v0.2.0`** 이 user_data 에 넣었다(변수 없이 항상)
> - `helm v3.21.3` · `argocd v3.5.0` = **이 커밋이 변수로 지정**했다(전엔 미지정이라 아예 없었다)
> - `argocd-seed.sh` = GitOps 저장소 `bootstrap/` 에 **vendoring** 됐다(gitops `ba9d079`)
>
> ⇒ 🔑 **교체가 곧 복구다.** 손으로 넣은 상태를 코드가 인수하는 것이 이 변경의 목적이다.
>
> ⛔ **재생성 중에는 클러스터 도달 경로가 끊긴다** — `endpoint_public_access = false` 라
> workbench 가 유일한 도달 지점이다. ArgoCD 는 클러스터 안에서 자율로 도므로 영향 없다.
> ⭐ **v0.2.0 과 v0.3.0 을 한 번에** 올려 교체를 1회로 묶었다.
>
> ⚠️ **apply 전 destroy/replace 목록을 사람이 읽는다**(공용 계정 — 예외 없음).
> plan 은 main push 로 돌고 **apply 는 `workflow_dispatch` 를 누르는 행위가 승인**이다.
>
> ### ✅ **plan 판정 완료 — 부수 피해 0** (PR #20 머지 `1f6ab8c` · run [`31352249270`](https://github.com/skax-ca/iac-reference-infra/actions/runs/31352249270))
>
> ```
> Plan: 1 to add, 0 to change, 1 to destroy.
>   # module.workbench.aws_instance.this[0] must be replaced
>   ~ user_data = <<-EOT # forces replacement
> ```
> 🔑 **replace 대상이 인스턴스 1개뿐이다.** IAM role·instance profile·SG·SG rule 이 목록에 **없다**
> ⇒ Access Entry(2층)·cluster SG ingress(3층)가 **그대로 유지된다**는 예측이 plan 으로 확인됐다.
> `0 to change` 라 다른 리소스의 in-place 변경도 없다.
>
> **user_data diff 실물**(`+` = 새로 들어가는 줄):
> `+ dnf install -y git-core` · `+ .../argocd-linux-$ARCH`(v3.5.0) · `+ .../helm-v3.21.3-...tar.gz`.
> `kubectl v1.35.7` 줄에는 `+` 가 없다(변경 없음) ⇒ **의도한 것만 들어갔다.**
>
> ⚠️ 판정은 워크플로 `success` 가 아니라 **로그 본문**으로 했다(이 repo 의 기존 규율).
>
> ### 🔴 **apply 결과 — 부분 실패**(run [`31352399365`](https://github.com/skax-ca/iac-reference-infra/actions/runs/31352399365))
>
> `Apply complete! Resources: 1 added, 0 changed, 1 destroyed.` — plan 대로 **부수 피해 0**.
>
> | 결과 | |
> |---|---|
> | ✅ SSM 재등록 `Online` · kubeconfig **첫 시도 성공** | IAM 전파 재시도 루프가 돌 필요조차 없었다 |
> | ✅ `kubectl v1.35.7` · `helm v3.21.3` · `argocd v3.5.0` | 전부 자동 설치 |
> | ❌ **`git` 미설치** | 부팅 중 `dnf` 가 **OOM-kill** 됐다(`total-vm 976MB`) |
>
> 🔑 **`free -m` 의 swap 417MB 는 여유가 아니었다** — 실물이 `/dev/zram0`(RAM 압축)이라
> 용량이 늘지 않는다. 판정은 `swapon --show` 로 한다.
> ⚠️ 2026-08-07 에 같은 명령이 **손으로는 성공**했었다(유휴 상태였기 때문) —
> **"수동으로 됐으니 자동으로도 된다"가 부팅 중 경합에서는 성립하지 않는다.**
>
> ⇒ 모듈 repo 가 **D-WORKBENCH-SIZE**(`40 §4.3`)로 기본 타입을 **`t4g.small`(2GB)** 로 올리고
> **`workbench-v0.4.0`** 을 컷했다. 다음 재핀이 `git` 을 회수한다.
>
> ### ✅ **v0.4.0 재핀 plan 판정** (PR #21 머지 · run [`31353415892`](https://github.com/skax-ca/iac-reference-infra/actions/runs/31353415892))
>
> ```
> Plan: 1 to add, 0 to change, 1 to destroy.
>   # module.workbench.aws_instance.this[0] must be replaced
>   ~ instance_type = "t4g.nano" -> "t4g.small"
>   ~ user_data     = <<-EOT # forces replacement
>   +   HOME=/root argocd version --client || true
> ```
> **replace 는 다시 인스턴스 1개뿐**이다 — IAM·SG 는 목록에 없다.
>
> ⏸ **여기서 멈춰 있다.** 다음은 `workflow_dispatch` 로 apply — **누르는 행위가 승인**이다.
> 🔴 apply 후 반드시 확인: **`git --version`**(이번 릴리스가 닫으려는 바로 그것) ·
> `free -m`(2GB) · `swapon --show` · `helm version` · `argocd version --client` · `kubectl get nodes`.

> ### ⚠️ **핀 표기가 여러 파일에 흩어져 재발한 drift** (2026-08-10 정정)
>
> `main.tf` 는 `eks-cluster-v0.4.0` 인데 **`AGENTS.md`(4곳)·`README.md`·`docs/deployment-facts.md`
> 가 `v0.1.0` 에 멈춰 있었다.** 같은 날 모듈 repo 예제 README 도 같은 유형이었다.
> 🔑 **`main.tf` 의 `?ref=` 가 유일한 사실이고 나머지는 전부 사본이다** — 사본이 늘수록 재발한다.
> 구조적 해법(핀을 한 곳에서만 표기)은 아직 판단하지 않았다.

모듈 repo 가 전 모듈을 **`0.y.z`(개발 단계)** 로 전환했다
(SSOT = 모듈 repo `docs/architecture/05-versioning-policy.md` = **D-VERSION**). 커밋 `81d6349`.

- **재매핑이지 업그레이드가 아니다** — 구 태그와 **같은 커밋**이라 모듈 내용은 그대로다.
  `vpc-v1.0.0/1.1.0/1.2.0` → `v0.1.0/v0.2.0/v0.3.0` · `eks-cluster-v1.0.0` → `v0.1.0`.
  **구 `1.x` 태그는 원격까지 삭제됐다** — 그 핀으로 되돌리면 `init` 이 실패한다.
- ✅ **판정**: 재핀 push 의 plan run 2개가 **`No changes.`**
  ([`30961419570`](https://github.com/skax-ca/iac-reference-infra/actions/runs/30961419570) networking ·
  [`30961419575`](https://github.com/skax-ca/iac-reference-infra/actions/runs/30961419575) eks).
  🔑 워크플로 `success` 가 아니라 **로그 본문**으로 판정했다 — 변경이 있어도 plan job 은 성공한다.
- ⚠️ **`0.y.z` 에서는 마이너 업그레이드도 계약을 바꿀 수 있다.** 태그를 올릴 때
  `git show <tag>` 로 릴리스 메시지를 읽는다 — 마이너라고 안전을 가정하지 않는다.
- ⛔ 아래 본문·`docs/deployment-facts.md` 에 남은 `v1.x` 번호는 **그때의 사실 기록**이다.
- 다음 모듈 릴리스 예정: **`eks-cluster-v0.2.0`**(D-EXTDNS-ZONE validation, 모듈 repo 작업).
- ⚠️ **로컬 경로는 머신별 상태다.** 이 머신은 `/Users/a07326/born2k/ai/iac-reference-infra`,
  다른 머신은 `/Users/born2k/silverte/ai/iac-reference-infra`. `backend.hcl`·AWS 프로파일·게이트 도구와
  같은 부류로 **clone·머신 단위**라 git·dotfiles 로 따라오지 않는다 — 새 머신에서 먼저 확인한다.

## 📍 지금 어디인가 (2026-07-31 기준)

```
✅1 골격+App소싱  ✅2 OIDC sub  ✅3 bootstrap  ✅4 apply(66개 생성)  ✅5 design/50 개정
   ✅6-2 계정정보 정리  ✅MCP(opentofu·aws-docs·aws-api)  ✅6-3 confused deputy  ✅6-1 prevent_destroy
🎉 미검증 6항목 전부 판정 · Phase 6 완결  ✅eks apply 완료(2026-08-04)
```

**🎉 Phase 6 완결(2026-07-31).** 미검증 6항목이 모두 판정됐다(판정표 SSOT = `docs/deployment-facts.md` §6).
남은 것은 정리성 미결 항목뿐(아래 「미결 항목」). **다음 방향은 사용자와 정한다** — 리허설 자산
teardown 여부(6-1은 파기 "거부"만 확인했고 실제 파기는 안 했다. NAT 월 ~$43 계속), 또는 새 작업.

**🔁 2026-08-03: vpc-v1.2.0 승격 1사이클 실증**(아래 「vpc-v1.2.0 승격」). 핀 한 줄 → PR#11 →
apply `0/20/0`(서브넷 태그 in-place). D20 소싱 규약의 정상 운영을 처음 한 바퀴 돌렸다.

**🆕 2026-08-03~04: live/dev/eks 배포 루트 + graviton·버전 핀**(아래 「live/dev/eks」).
PR#13(루트 신설) · **PR#12(D30-1)** · **PR#14**(graviton+핀+rename+§8) 전부 **merge**.
**✅ 2026-08-04: EKS apply 완료(2회 dispatch)** — 클러스터 ACTIVE, graviton 노드그룹 running.
비용 발생: ~$165/월 + Flow Logs.
**🆕 2026-08-05: 모듈 핀 `eks-cluster-v0.2.0` + external-dns 제거 apply 완료** — **현행 addon 7종**
(구 8종 기록은 08-04 시점이다). ⛔ **external-dns 는 "일시 중단"이 아니라 기본값**이고
**"upstream fix 대기"는 기각됐다**(AWS IAM 제약이라 기다릴 대상이 없다) — 아래 D-EXTDNS-ZONE 절.

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
| repo 변수/시크릿 | `MODULE_READER_CLIENT_ID`(변수, client-id=`Iv23…`) · `MODULE_READER_KEY`(secret) |

> 🔁 **2026-07-31 전환**: `create-github-app-token@v3.2.0`이 `app-id`를 legacy 경고 → `client-id`로 옮김.
> 낡은 `MODULE_READER_APP_ID`(숫자 `4432001`) 변수는 **삭제**했다. client-id는 App ID와 **다른 값**이고
> public `/apps/{slug}`로 조회된다. plan+apply 두 job 모두 client-id로 토큰 발급 실증([PR#10](https://github.com/skax-ca/iac-reference-infra/pull/10)).

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
- ✅ **2026-08-06: 모듈 repo `.mcp.json`과 다시 같아졌다.** 구 기록은 *"의도적으로 다르다 —
  aws-api는 배포 검증 도구라 소싱만 하는 모듈 repo엔 불필요"* 였고 **그때는 옳았다.**
  바뀐 것은 모듈 repo의 역할이다 — `40 §5.1`이 *"apply 판정이 나면 `40`에 기록한다"* 로 정해
  그쪽도 **실계정 판정을 받아 적는 쪽**이 됐다(모듈 repo notepad의 MCP 절에 근거 전문).
  ⚠️ 그래도 **모듈 repo는 배포하지 않는다** — 조회가 생겼다고 "apply로 검증했다"가 되지 않는다.
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

### ✅ 6-1 `prevent_destroy` 판정 **완료** (2026-07-31, 사용자 결정 = "파기 거부만 확인·자산 유지")

**방식**: 검증 PR [#9](https://github.com/skax-ca/iac-reference-infra/pull/9)에 `vpc_enabled = false`(+ 기존 `deletion_protection = true`)를
걸어 **보호를 켠 채 파기를 시도** → CI plan job이 D12 교차변수 validation으로 **거부**:
`deletion_protection = true인 상태에서는 vpc_enabled = false로 파기할 수 없다`. **apply skip, 66개 자산 그대로.**
PR은 merge 없이 닫음(자산 유지). run [`30605752914`](https://github.com/skax-ca/iac-reference-infra/actions/runs/30605752914).

**🔑 실측 2건**
1. **pre-push `validate`는 이 조합을 못 잡는다** — 교차변수 validation은 validate가 아니라 **plan 시점**에
   평가된다(모듈 주석 실측과 일치). 그래서 push는 통과하고 **CI plan**에서 걸렸다. 어느 게이트가 무엇을
   잡는지가 실증됐다.
2. **§7 정직성 — 판정된 건 validation 가드**다(`deployment-facts.md` §6 각주 ¹ 참조).
   D12의 다른 절반인 **`prevent_destroy` lifecycle 메타 인자**(`tofu destroy`·replace 차단)는 라이브 plan에
   존재하고 모듈 계약 테스트가 증명하나, destroy-plan을 **별도 라이브 실행하진 않았다**(deploy.yml에
   destroy 경로 없음 + 자산 유지 결정). 두 가드를 뭉뚱그리지 않는다.

⚠️ **실제 파기는 하지 않았다.** teardown 2단계(`deletion_protection=false` apply → `vpc_enabled=false` apply)는
자산을 없앨 때 밟는다. NAT 월 ~$43은 계속 과금 중.

---

## ✅ vpc-v1.2.0 승격 — 첫 마이너 버전 반영 사이클 실증 (2026-08-03)

**미해결 항목 아님 — D20 소싱 규약의 정상 운영을 처음으로 한 바퀴 돌렸다.** 모듈 repo가
`vpc-v1.2.0`(D13 SubnetGroup 태그, `feat 4f44dd8`)를 릴리스 → 소비 루트에 반영.

소비 [PR#11](https://github.com/skax-ca/iac-reference-infra/pull/11)(merge `c1fa847`) · apply run [`30788555076`](https://github.com/skax-ca/iac-reference-infra/actions/runs/30788555076).

| 판정 | 실측 |
|------|------|
| 반영 = 핀 한 줄 | `live/dev/networking/main.tf:62` `vpc-v1.1.0` → `vpc-v1.2.0`. `variables.tf` diff **0** → 루트 인자 무변화 |
| plan (PR 댓글) | `0 add / 20 change / 0 destroy` · destroy/replace 대상 **`(없음)`** |
| apply | **`Apply complete! Resources: 0 added, 20 changed, 0 destroyed`** — 서브넷 20개 태그 in-place |

**🔑 실측/판정 3건**
1. **마이너 버전 반영의 정체는 "핀 한 줄 커밋"이다** — 변수 인터페이스가 안 바뀌면(diff 0) 루트는
   호출 인자를 손대지 않는다. 인터페이스가 바뀌었다면 루트 호출도 함께 고쳐야 한다(이번엔 아니었다).
2. **태그 추가 = in-place, replace 아님.** `main.tf` diff(태그 1줄 추가)를 미리 읽어 판정했고
   실측이 확인(`0 destroyed`). 공용 계정(§4-1)에서 **예상과 실측 일치**가 안전의 판정 기준이다.
3. **`ignore_tags`와 무충돌.** `SubnetGroup`은 모듈이 state에 넣는 관리 태그라 자동 태거 `cz-*`처럼
   무시되지 않는다 → 정상 diff로 잡혀 적용됐다.
4. **"승인=적용"이 로그로 증명됐다.** PR 댓글 `0/20/0` = apply `0/20/0`. apply job이 저장된
   plan artifact를 `tofu apply tfplan`으로 그대로 먹어(재-plan 없음) 검토 대상과 적용 대상이 동일.

ℹ️ **직전 승격(`v1.0.0→v1.1.0`)은 Flow Logs IAM in-place였다**(`deployment-facts.md:427`, `0/1/0`).
이번이 **서브넷 20개**로 대상이 넓어진 두 번째 승격이다. 둘 다 destroy/replace 0 — 소싱 승격이
정상 운영에서 어떤 모습인지의 표본이 둘 생겼다.

---

## 🆕 live/dev/eks 배포 루트 (2026-08-03) — vpc·eks 독립 배포, 코드만 추가

**사용자 결정**: vpc·eks 독립 배포 · enterprise 프로파일 · public-restricted · **코드만 추가(EKS apply 안 함)**.
소비 [PR#13](https://github.com/skax-ca/iac-reference-infra/pull/13) **merge됨**(`c09e6fc`, 2026-08-03).
모듈 태그 **`eks-cluster-v1.0.0`** 컷(모듈 repo a530b74, annotated, push됨).

### merge 결과 (2026-08-03) — 두 워크플로 트리거
- `deploy · live/dev/eks`(run 30862982175): plan **`71 to add, 0 change, 0 destroy`** clean · **apply skip**
  (D30-1 dispatch 전용). EKS 리소스 **미생성 · 비용 없음**. 71 리소스가 실계정에서 계획됨 = data source
  조회·모듈 조합·public_access_cidrs 주입 전부 실증(plan 수준).
- `deploy · live/dev/networking`(run 30862982181): networking main.tf 변경이 **구 형태 워크플로로 자동 apply**
  → **`0 added, 6 changed, 0 destroyed`**(pub/elb 서브넷 4개 cluster 태그 -main→-main-01 + node 서브넷 2개
  karpenter 태그, 전부 in-place). ⚠️ 이 repo 기존 동작(networking merge=자동 apply, PR#12 전까지). **pre-apply
  항목 3(networking 선행) 충족됨.**
- repo 변수 **`EKS_PUBLIC_ACCESS_CIDRS = ["211.45.60.3/32"]`** 설정됨(사용자 IP, /32). **pre-apply 항목 1 충족.**

### 독립 배포 메커니즘 (핵심)
- **state 분리**: `dev/eks.tfstate`. networking state 를 읽지 않는다.
- **결합은 태그 data source 로만**: `data.aws_vpc`(tag:Name+Workload) · `data.aws_subnets`
  (tag:SubnetGroup=node-uniq/pod-dup, **vpc-v1.2.0 D13**). **remote_state 미사용**(03 §3.1).
  → vpc 먼저 없으면 plan 이 빈 결과로 **명확히 실패**(조용한 오작동 아님). 파기는 역순.
- 공유하는 것은 state 가 아니라 **클러스터명 상수** `eks-ref-dev-an2-main-01` — 결합이 아니라 규약.

### 🔑 발견/판정 3건
1. **latent 정합성 버그 수정**(PR#13 커밋 1 `fix(networking)`): networking 의 `eks_cluster_name` 이
   `-main`(serial 없음)이었다. 모듈은 클러스터명에 **serial 을 항상 포함**(`eks-<mid>-<purpose>-<serial>`)
   → 실제 `-main-01`. 어긋나면 서브넷 디스커버리 태그가 실제 클러스터명과 불일치 → ELB/Karpenter
   selector 빈 결과 → **조용한 실패**. `-main-01` 로 고치고 node-uniq 에 karpenter.sh/discovery 태그 추가.
   ⚠️ 다음 networking apply 시 pub/elb 서브넷 cluster 태그 키 변경 + node 서브넷 태그 추가(전부 in-place).
2. **EKS 모듈 provider 요구는 aws>=6.0 하나뿐**(k8s/helm 은 GitOps 소관). 루트 providers.tf 가 단순.
   init 소싱 확인: eks-cluster-v1.0.0 + terraform-aws-modules/eks 21.24.1 · kms · eks-pod-identity.
3. **trivy findings 는 전부 업스트림 모듈**(AWS-0040 public access CRITICAL · 0038 로깅 · 0104 egress).
   `--tf-exclude-downloaded-modules`(훅)로 제외 = 우리 루트 clean. .trivyignore 정책대로 배포 루트에서
   안 덮는다 — public access 수락은 모듈 설계 판단이고 소비자가 CIDR 제한과 함께 opt-in 한 것.

### ✅ EKS apply 완료 (2026-08-04, dispatch 2회)

**[run 30878573785](https://github.com/skax-ca/iac-reference-infra/actions/runs/30878573785) — `0 add / 0 change / 2 destroy`**

두 번째 dispatch 성공. 첫 번째 dispatch(run 30877358485)가 `external_dns_iam` IAM 정책 생성에서
**400 MalformedPolicyDocument**로 실패하기 **직전에** 클러스터·노드그룹·addon을 state에 생성했다.
두 번째 dispatch는 `enable_external_dns_iam=false` 변경분을 감지해 **external_dns IAMRole+association 2개만 파기**했다.

**실계정 확인** (run 직후):
- 클러스터 `eks-ref-dev-an2-main-01` — **ACTIVE**, k8s 1.35
- 노드그룹 `eksn-ref-dev-an2-system` — t4g.medium×2 (graviton)
- addon 8종 모두 존재: aws-ebs-csi-driver · cert-manager · coredns · eks-pod-identity-agent ·
  external-dns · kube-proxy · metrics-server · vpc-cni
- deletion_protection=true (콘솔에서도 삭제 불가)

**🔑 실측: 첫 apply 실패 시에도 클러스터는 이미 생성된다.**
`eks module`은 리소스 타입이 많아 plan 71개 중 **IAM Role · SG · KMS · EKS cluster 자체**가
순서대로 state에 write되고, 실패 시점에 도달한 지점에서 멈춘다. 재apply는 state를 읽어
**이미 있는 것 → plan 0, 없던 것 → 2 destroy**(external_dns IAM만).
이것이 `tofu apply`의 원자성이 아니라 AWS API의 프로비저닝 타이밍에 기인하는 속성임이 실증됐다.

**⛔ `external_dns_iam` 일시 중단 — upstream 버그(D-NODE-ARCH 유사).**
`external_dns_hosted_zone_arns=[]` 빈 배열을 넘기면 upstream이 `Resource="*"`인 IAM 정책을 만들지만,
`route53:ChangeResourceRecordSets`는 리소스 수준 권한이라 AWS가 400으로 거부한다.
재개 조건: (1) dev hosted zone bootstrap 또는 (2) upstream fix 후 module 승격.
GitOps helm 설치 시 IAM은 별도 처리한다.

> ⚠️ **위 두 줄은 2026-08-04 당시의 기록이며 2026-08-05에 개정됐다**(아래 D-EXTDNS-ZONE 절).
> **"일시 중단"이 아니라 기본값**이고, **재개 조건 (2)는 기각됐다** — upstream 버그가 아니라
> AWS IAM 제약이라 기다릴 대상이 없다. 이 문단은 사실 기록으로만 읽는다.

### pre-apply 상태 (EKS README §4) — **전부 충족, apply 완료**
- ✅ repo 변수 `EKS_PUBLIC_ACCESS_CIDRS = ["211.45.60.3/32"]`.
- ✅ networking 선행 apply 완료(6 changed — 태그 in-place).
- ✅ `ami_release_version = 1.35.6-20260728` 핀(**arm64** SSM 경로. 아키텍처별로 값이 다르다).
- ✅ **EKS apply 완료** — `dispatch run 30878573785`, 클러스터 ACTIVE, 노드그룹 running, 8종 addon 등록.

### ✅ 2026-08-04 추가분 — graviton · 버전 핀 · 워크플로 rename · 작업 원칙

소비 [PR#14](https://github.com/skax-ca/iac-reference-infra/pull/14)(`47e1a23`) · 모듈 [PR#10](https://github.com/skax-ca/iac-module-library/pull/10)(`74bbf51`) · 모듈 `401b920`.

1. **graviton — 🔴 모듈 변경이 필요했다(D-NODE-ARCH 신설)**. `t4g.medium` + `ami_type = AL2023_ARM_64_STANDARD`.
   **facade 에 `ami_type` 이 없어 소비 루트만으로는 불가능**했다 — upstream 기본이 x86 고정이라
   arm 인스턴스만 넣으면 **노드가 부팅되지 않는다**(plan 은 통과). 비용 $170→$48/월.
   🔑 **실패 유형**: "upstream 미지원"이 아니라 **wrapper 가 안 넘기고 있었을 뿐**. upstream v21.24.1 엔
   처음부터 있었다. 소스를 안 열고 단정했으면 launch template 우회를 짰을 것이고 그게 drift다.
2. **addon 8종 + AMI 버전 핀** — D-ADDON-VERSION-PIN-1 을 코드가 이행하지 않고 있었다.
   🔑 **최신이 아니라 AWS 기본(default) 버전을 박는다** — 기본을 박으면 핀 전후 동작이 같다.
   최신을 박으면 "핀 추가"에 업그레이드 결정이 섞인다(실측: coredns 기본 `v1.13.2-eksbuild.11` ≠ 최신 `v1.14.3-eksbuild.3`).
   ⚠️ k8s 버전을 올리면 **addon 8종 + ami_release_version 을 한 커밋에서 함께** 갱신한다.
3. **`deploy.yml` → `deploy-network.yml`**(git mv). ⚠️ 함께 정정: PR#12 merge 로 **CLAUDE.md 가 거짓이
   됐었다** — "PR 댓글을 읽고 merge = 검토 지점"인데 PR plan 트리거가 사라져 **댓글 자체가 없다.**
   → 검토 지점은 **workflow_dispatch 를 누르는 행위**.
4. **§8 작업 원칙 채택**(두 repo). 🔴 그대로 옮기면 틀리는 2개를 번역: *"하위호환 유지 마라"* → 죽은
   **코드**는 삭제하되 **계약** 파괴는 semver 로 드러낸다(태그 덮어쓰기는 **소비자 0일 때만**) ·
   *"가장 단순한 구현"* → 안전장치(prevent_destroy·validation)는 추측 대비가 아니라 현재 요구사항.

**🔑 태그 이동 선례**: `eks-cluster-v1.0.0` 을 D-NODE-ARCH 포함 커밋으로 **force 이동**했다(사용자 결정).
apply 된 인프라가 0 이라 비용이 없었다. ⛔ **한 번이라도 apply 된 뒤에는 마이너를 컷한다.**

**ℹ️ 워크플로 트리거는 이미 선택적이다**(2026-08-04 실측): PR#12(워크플로 1개만 변경) → **networking 만**
돌고 eks 는 안 돌았다. PR#14 에서 둘 다 돈 것은 **rename 이 자기 참조 경로에 걸린 일회성**이고,
networking plan 결과가 `No changes` 였다. → 경로 필터를 더 좁히지 않기로 결정(§8-3).

### 💰 apply 시 비용
EKS 컨트롤플레인 ~$73/월 + system NG m6i.large×2 ~$170/월 + 컨트롤플레인 로그. 기존 NAT $43/월 위.

### ✅ 2026-08-05 — 모듈 핀 `eks-cluster-v0.2.0` + external-dns 미탑재 확정 (D-EXTDNS-ZONE)

커밋 `3331eaa`(main 직접). 모듈 repo PR [#11](https://github.com/skax-ca/iac-module-library/pull/11) 종결분을 반영했다.

**✅ apply 완료** — push plan run [`30968180122`](https://github.com/skax-ca/iac-reference-infra/actions/runs/30968180122) →
dispatch run [`30968371410`](https://github.com/skax-ca/iac-reference-infra/actions/runs/30968371410).

```
# module.eks.module.eks.aws_eks_addon.this["external-dns"] will be destroyed
Plan: 0 to add, 0 to change, 1 to destroy.
→ Destroying... [id=eks-ref-dev-an2-main-01:external-dns]
→ Apply complete! Resources: 0 added, 0 changed, 1 destroyed.
```

✅ **실계정 독립 확인**: `aws eks list-addons` = **7종**(8종에서 `external-dns` 빠짐) —
`vpc-cni`·`coredns`·`kube-proxy`·`eks-pod-identity-agent`·`aws-ebs-csi-driver`·`metrics-server`·`cert-manager`.
🔑 apply 로그의 성공만으로 끝내지 않았다 — 이 repo 의 판정 기준은 실물 조회다.

- ⭐ **핀 상향의 diff 가 0이라는 것이 증거다.** `v0.1.0 → v0.2.0` 은 교차변수 validation 추가뿐이라
  리소스에 영향이 없어야 하는데 plan 이 그것을 실증했다. 여기서 예상치 못한 change 가 나왔다면
  릴리스가 계약을 몰래 바꿨다는 뜻이다 — **`0.y.z` 구간에서 특히 확인할 가치가 있는 지점**이다.
- **destroy 1건 = `external-dns` addon.** IAM 이 꺼져 있어 이 컨트롤러는 Route53 에 아무것도 쓰지
  못한 채 돌고 있었다(죽은 경로). ⭐ **addon 과 IAM 은 한 쌍**이라 함께 끈다 — 되켤 때도 함께 켠다.
- ⛔ **"upstream fix 대기"는 기각됐다.** upstream 버그가 아니라 **AWS IAM 제약**이고
  (`route53:ChangeResourceRecordSets` 는 리소스 수준 권한), 조합을 막는 것은 facade 의 일이라는 것이
  D-EXTDNS-ZONE 의 판단이다. 모듈 `v0.2.0` 이 이제 그 조합을 **plan 에서** 거부한다.
- **되켜는 법**: dev hosted zone 확보 → `data.aws_route53_zone` 으로 **조회**해 ARN 을 넘기고
  addon 도 함께 되살린다. ⛔ **zone 은 이 루트가 소유하지 않는다** — 워크로드 수명주기보다 오래 산다.
  (모듈 repo `examples/eks-cluster-enterprise/README.md` "external-dns" 절이 안내 SSOT)
- ⚠️ **이 머신에는 `backend.hcl` 이 없어 로컬 plan 이 불가하다**(D25 partial backend).
  로컬은 `fmt`·`validate`·`init` 까지가 한계이고 **판정은 CI plan** 이 한다.
- ✅ **`team` 프로파일 해소**(2026-08-05, 사용자가 이 머신에 설정). 최초 확인 때는 없어서
  임시로 다른 프로파일로 조회했으나, 지금은 **CLAUDE.md 규약대로 `--profile team` 이 동작한다**
  (`list-addons` 7종 재확인 완료 — 같은 결과).
  🔑 게이트 도구와 같은 유형의 **머신별 상태**다. `brew` 설치·`git config`·`backend.hcl`·
  AWS 프로파일은 **clone·머신 단위**라 dotfiles 동기화로 따라오지 않는다 — 새 머신에서 먼저 확인한다.

---

### ✅ 마무리 2건 (2026-08-06) — **plan 이 `No changes` 가 됐다**

#### 1. `volume_tags` drift → `ignore_tags` 로 해소 (PR [#18](https://github.com/skax-ca/iac-reference-infra/pull/18))

⭐ **해법이 이미 repo 안에 있었다.** `providers.tf` 의 `ignore_tags` 는 2026-07-31 networking 에서
같은 유형을 잡으려고 세운 것이고, `DependencyID`·`DependencyName` 만 목록에서 빠져 있었다.
`lifecycle ignore_changes` 를 모듈에 넣거나 `volume_tags` 구조를 바꾸는 것은 **이미 있는 장치를
못 보고 우회하는** 형태였을 것이다.

- 실측: **볼륨 전용**(계정 전수 15건 전부 `ResourceType: volume`) · **생성 이벤트 기반**(재부착 없음)
- 그래도 넣은 이유: `user_data_replace_on_change = true` 라 **도구 버전·AMI 핀을 올리면 재생성**되고
  그때마다 같은 가짜 diff 가 난다
- ⚠️ **networking 에는 안 넣었다** — 볼륨을 만들지 않는다. 두 루트의 `ignore_tags` 가 다른 것은
  **의도**이니 "parity 복원"으로 맞추지 말 것(주석에 명시)
- ⚠️ **`Name` 은 막지 않았다** — 같은 태거가 볼륨 `Name` 도 덮지만 `Name` 은 네이밍 계약이라
  무시하면 **모든 `Name` 규약이 함께 눈이 먼다**. tofu 가 되돌리는 것이 정답이고
  **볼륨 생성당 1회** diff 로 끝난다(반복 아님)

#### 2. `public_access_cidrs` 영구 diff → `eks-cluster-v0.4.0` (PR [#19](https://github.com/skax-ca/iac-reference-infra/pull/19))

핀 한 줄만 올렸다(계약 무변경). plan
[`31080181294`](https://github.com/skax-ca/iac-reference-infra/actions/runs/31080181294)
= **`No changes. Your infrastructure matches the configuration.`**

> 🔑 **빈 컬렉션은 "없음"이 아니라 "있음"이다** — provider 문서: *"drift detection ... **when
> present in a configuration**."* `null` 만 "없음"이다. 모듈이 기본값 `[]` 를 그대로 넘겨서,
> 우리가 인자를 지웠는데도 diff 가 났다. 근거 전문은 모듈 repo `20 §4.4`(D-EKS-CIDR-NULL).
>
> ⭐ **OIDC `thumbprint_list` 도 함께 사라졌다** — 별개 항목이라 봤던 판단이 틀렸다.
> `(known after apply)` 는 **다른 리소스 변경에 의존할 때** 뜨므로, 클러스터 diff 가 사라지자
> 연쇄로 없어졌다. ⇒ **의존 리소스의 diff 를 먼저 닫고 다시 본다.**

⚠️ **`EKS_PUBLIC_ACCESS_CIDRS` repo 변수 삭제 완료.** 남은 변수 4개:
`AWS_ENTRY_ROLE_ARN` · `AWS_EXEC_ROLE_ARN` · `MODULE_READER_CLIENT_ID` · `TF_STATE_BUCKET`.

### 🔬 `endpoint_private_access = true` 가 실제로 하는 일 (2026-08-06 실측)

스위치 하나로 보이지만 **AWS 가 3개를 조립**한다. 진단할 때 이 셋을 나눠 본다:

| 조립물 | 실측값 |
|--------|--------|
| **cross-account ENI**(경로) | `eni-02eaaae3f33f96a13`·`eni-004d81156c35330d1` — owner=우리 계정, **requester=`441647948811`(AWS EKS)**, `RequesterManaged: true`. `subnet_ids`(node-uniq)에 **AZ 당 1개씩 IP 를 소모**한다 |
| **private hosted zone**(이름) | `Z09127421NJ9XYMXFJ640`, `OwningService: eks.amazonaws.com`, 우리 VPC 에 연결 → **split-horizon DNS**. 같은 호스트명이 VPC 안에서만 private IP 로 해석된다 |
| **SG 부착**(허용) | 그 ENI 에 `sg-011c…`(upstream cluster SG — 우리 workbench 규칙이 여기) + `sg-0b42…`(EKS 자동 생성 primary) |

⚠️ **전제**: VPC 의 `enableDnsSupport`·`enableDnsHostnames` 가 켜져 있어야 zone 이 동작한다.
⭐ 세 번째 항목이 `eks-cluster-v0.3.0` 이 출력 설명을 정정한 이유의 **실물 확인**이다 —
3층 규칙이 붙은 SG 가 실제로 apiserver ENI 에 적용된다. 다른 SG 였다면 `i/o timeout` 이다.

## 💰 현재 진행 중 비용

| 루트 | 상태 | 월 비용 |
|------|------|---------|
| `live/dev/networking` | 66개 리소스 apply 완료 | NAT Gateway ~$43 + Flow Logs CloudWatch |
| `live/dev/eks` | **apply 완료** (run 30878573785) | EKS 컨트롤플레인 ~$73 + system t4g.medium×2 ~$48 + 컨트롤플레인 로그 |

총 예상: **~$165/월 + Flow Logs** (nat $43 + eks $122).

### ⚠️ 과잉 주장 금지

판정표 SSOT는 `docs/deployment-facts.md` §6. **✅가 찍힌 것만 실증했다고 쓴다.**
✅ **미검증 6항목 전부 판정됐다**(6-1 각주 ¹의 validation/lifecycle 구분 포함). 그래도
**실제 파기는 안 했다** — teardown 2단계(`deletion_protection=false` → `vpc_enabled=false`)는
자산 정리를 결정할 때 밟는다.

## 🎉 2026-08-06 — workbench 배선·개명·**private-only 전환 완결**

**✅ ①apply ②SSM ③kubectl ④public 차단 — 4단계 전부 끝났다.**

### PR #15 — workbench 3층 배선 + 모듈 핀 v0.3.0

| 항목 | 내용 |
|------|------|
| 모듈 핀 | `eks-cluster-v0.2.0` → **`v0.3.0`** — 순수 추가 릴리스라 plan 이 **`0 to change`** 로 실증했다 |
| 신규 모듈 | **`workbench-v0.1.0`** — `vm-uniq` private 서브넷, t4g.nano(arm64), SSM 전용(인바운드 0) |
| 2층 | `access_entries` — workbench role → `AmazonEKSClusterAdminPolicy` |
| 3층 | `cluster_security_group_additional_rules` — workbench SG → apiserver 443 |
| 출력 | `workbench_instance_id` (SSM 접속 대상) |

⭐ **핀 상향의 diff 가 0이라는 것이 증거다.** v0.3.0 은 `cluster_security_group_additional_rules`
신설 + `required_version` 하한뿐이라 기존 리소스에 영향이 없어야 하는데 plan 이 그것을 실증했다.
`0.y.z` 구간에서 마이너를 올릴 때마다 확인할 가치가 있는 지점이다.

### PR #16 — bastion → workbench 개명 (D-WORKBENCH-RENAME)

이름이 실물과 어긋나 있었다 — `bastion host` 의 정의는 *인바운드를 받아 안쪽으로 전달*인데
이 모듈은 **인바운드 규칙이 0개**다. 요새가 아니라 **도구가 갖춰진 작업대**다.
근거 전문은 모듈 repo `docs/design/40-workbench.md §2.0`.

- ⛔ **구 태그 `bastion-v0.1.0` 은 원격에서 삭제됐다.** 그 핀으로 되돌리면 `init` 이 실패한다.
- ⏱️ **apply 전이라 공짜였다.** `purpose` 는 태그가 아니라 **식별자**로 흘러간다
  (`aws_iam_role.name` · `aws_iam_instance_profile.name` · `aws_security_group.name`) —
  apply 후였다면 그 셋이 replace 되고 Access Entry·cluster SG rule 까지 연쇄 replace 됐다.
  🔑 일반화: *"purpose·naming 토큰을 바꾸는 개명은 apply 전에만 공짜다."*
- ✅ **판정**: 개명 후 plan 이 **개명 전과 숫자가 같다.**
  [`31056930396`](https://github.com/skax-ca/iac-reference-infra/actions/runs/31056930396)(개명 전) ·
  [`31058277158`](https://github.com/skax-ca/iac-reference-infra/actions/runs/31058277158)(개명 후)
  둘 다 **`Plan: 10 to add, 0 to change, 0 to destroy`**. Name 도 `-workbench-01` 로 확인.

### ✅ apply·도달 실증 완료 (2026-08-06)

run [`31059712680`](https://github.com/skax-ca/iac-reference-infra/actions/runs/31059712680)
= **`Apply complete! Resources: 10 added, 0 changed, 0 destroyed.`** 인스턴스 `i-04ac14a6f5891492c`.

✅ **실계정 조회로 대조했다** — 이 repo 판정 기준은 apply 로그가 아니라 실물이다:

| 계약 | 실물 |
|------|------|
| 배치 | `ap-northeast-2c` · `subnet-074f0b4094109f277`(vm-uniq) · `10.51.20.186` |
| ⭐ 공인 IP 미할당 | `PublicIpAddress: null` |
| ⭐ 키페어 미지정 | `KeyName: null` |
| ⭐ **인바운드 0개** | `length(IpPermissions) == 0` · egress 는 443/tcp 하나 |
| 아키텍처 정합 | `t4g.nano` + `ami-0973292651cddee46`(AL2023 arm64) 부팅 성공 |

⭐ 3개는 모듈 repo `40 §5.1` 이 *"`tofu test` 로 지킬 수 없다"* 고 적은 항목이다
(*"미지정 자체가 계약"* 인데 plan 에선 `known after apply`). **여기서 처음 실증됐고
모듈 repo `40 §7.3-1` 에 기록했다.**

**도달 3층 전부 성립**:
```
SSM 등록      PingStatus: Online · agent 3.3.4851.0 · AL2023
cloud-init    status: done                     ← 비동기라 kubectl 확인 전에 먼저 본다
1층           /etc/kubernetes/kubeconfig 생성됨(2447B)
kubectl       Client Version: v1.35.7          ← 클러스터 1.35 와 마이너 일치
2·3층         kubectl get nodes → 노드 2개 Ready
```
🔑 **`get nodes` 가 반환된 것 자체가 3층 전부의 증거다.** 실패했다면 층별로 다른 에러가 났다.

⚠️ **판정 방식**: 대화형 `start-session` 이 아니라 **`ssm send-command`**(AWS-RunShellScript)다
— 자동화 환경에 TTY 가 없다. 같은 채널·IAM·SG 를 지나므로 도달성으로는 동등하다.
사람이 붙을 때: `aws ssm start-session --profile team --region ap-northeast-2 --target i-04ac14a6f5891492c`

### ✅ ④ private-only 전환 완결 (2026-08-06) — 이 배포의 목적 달성

PR [#17](https://github.com/skax-ca/iac-reference-infra/pull/17) 머지 · apply run
[`31062408357`](https://github.com/skax-ca/iac-reference-infra/actions/runs/31062408357)
= **`0 added, 2 changed, 0 destroyed`**(클러스터 `vpc_config` **in-place** — replace 없음).

⭐ **음성 대조군이 이 판정의 핵심이다.** workbench 에서 kubectl 이 되는 것만으로는
*"private 경로로 닿았다"* 가 증명되지 않는다 — public 을 통해 닿고 있었을 수 있다.
**양쪽을 함께 봐야** 배제된다:

| | 결과 |
|---|---|
| 클러스터 실물 | `endpointPublicAccess: **false**` · `endpointPrivateAccess: true` · ACTIVE |
| **음성** VPC 밖 DNS | `10.51.37.9` · `10.51.36.184` — **private IP 만** |
| **음성** VPC 밖 `curl <endpoint>/version` | **timeout(12s)** · `http=000` |
| **양성** workbench DNS | 같은 private IP 2개 |
| **양성** workbench `kubectl get nodes` | 노드 2개 Ready · pod **21개 Running** |

ℹ️ plan 3건 → apply 2건. OIDC `thumbprint_list` 가 `(known after apply)` 였는데 재계산 결과가
기존 값과 같아 **no-op** 이 됐다 — `known after apply` 는 *"바뀔 수도 있다"* 이지 *"바뀐다"* 가 아니다.

**함께 걷어낸 것**: `public_access_cidrs` 변수·`TF_VAR_` 주입·README/AGENTS 기술.
⭐ **덤으로 D25 위반 1건** — `AGENTS.md` pre-apply 표에 **운영자 실제 IP 가 커밋돼 있었다.**
변수 설명이 *"출발지 IP 는 git 에 두지 않는다"* 를 적고 있는 동안 문서가 값을 노출하고 있었다.
🔑 **주입 경로를 막아도 문서가 값을 흘릴 수 있다.**

### ⚠️ 이번에 드러난 실측 2건 — 다음 apply 때 놀라지 말 것

1. **`publicAccessCidrs` 는 `describe-cluster` 응답에 남는다.** public 을 끄고 인자를 지워도
   AWS 가 **직전 값을 계속 반환**한다(운영자 IP `/32`). 동작에는 영향이 없는 무효 필드다.
   🔑 *"인자를 지우는 것과 값이 사라지는 것은 다르다."* git 에서는 지웠지만 API 응답에는 남아 있다.
2. **공용 계정의 다른 자동화가 EBS `volume_tags` 를 덮는다** — `DependencyID`·`DependencyName` 추가 +
   `Name` 을 인스턴스 이름으로 변경. tofu 가 매번 되돌리므로 **apply 마다 반복되는 drift** 다.
   무해하지만 `0 changed` 를 기대할 수 없게 만든다(아래 미결 항목에 등재).

### ⛔ 이제 workbench 가 **유일한** 도달 지점이다

접근이 필요하면 public 을 다시 여는 것이 아니라 **workbench 를 고친다** — 여는 것은 설계 목적
(모듈 repo `40 §1`)을 되돌리는 결정이다.

```
aws ssm start-session --profile team --region ap-northeast-2 --target i-04ac14a6f5891492c
# 세션 안에서 KUBECONFIG 는 /etc/profile.d/kubeconfig.sh 가 export 한다
```

⚠️ **`workbench_enabled = false` 로 내리기 전에 다른 경로를 확보한다.** 지금은 이것이 끊기면
클러스터를 만질 방법이 없다.

⚠️ GitHub **repo 변수 `EKS_PUBLIC_ACCESS_CIDRS` 는 콘솔에서 지워야 한다**(코드 밖 작업, 미완).

## 💰 현재 진행 중 비용

| 루트 | 상태 | 월 비용 |
|------|------|---------|
| `live/dev/networking` | 66개 리소스 apply 완료 | NAT Gateway ~$43 + Flow Logs CloudWatch |
| `live/dev/eks` | **apply 완료** (run 30878573785) | EKS 컨트롤플레인 ~$73 + system t4g.medium×2 ~$48 + 컨트롤플레인 로그 |

총 예상: **~$165/월 + Flow Logs** (nat $43 + eks $122).

### ⚠️ 과잉 주장 금지

판정표 SSOT는 `docs/deployment-facts.md` §6. **✅가 찍힌 것만 실증했다고 쓴다.**
✅ **미검증 6항목 전부 판정됐다**(6-1 각주 ¹의 validation/lifecycle 구분 포함). 그래도
**실제 파기는 안 했다** — teardown 2단계(`deletion_protection=false` → `vpc_enabled=false`)는
자산 정리를 결정할 때 밟는다.

## 🎉 2026-08-06 — workbench 배선·개명·**private-only 전환 완결**

**✅ ①apply ②SSM ③kubectl ④public 차단 — 4단계 전부 끝났다.**

### PR #15 — workbench 3층 배선 + 모듈 핀 v0.3.0

| 항목 | 내용 |
|------|------|
| 모듈 핀 | `eks-cluster-v0.2.0` → **`v0.3.0`** — 순수 추가 릴리스라 plan 이 **`0 to change`** 로 실증했다 |
| 신규 모듈 | **`workbench-v0.1.0`** — `vm-uniq` private 서브넷, t4g.nano(arm64), SSM 전용(인바운드 0) |
| 2층 | `access_entries` — workbench role → `AmazonEKSClusterAdminPolicy` |
| 3층 | `cluster_security_group_additional_rules` — workbench SG → apiserver 443 |
| 출력 | `workbench_instance_id` (SSM 접속 대상) |

⭐ **핀 상향의 diff 가 0이라는 것이 증거다.** v0.3.0 은 `cluster_security_group_additional_rules`
신설 + `required_version` 하한뿐이라 기존 리소스에 영향이 없어야 하는데 plan 이 그것을 실증했다.
`0.y.z` 구간에서 마이너를 올릴 때마다 확인할 가치가 있는 지점이다.

### PR #16 — bastion → workbench 개명 (D-WORKBENCH-RENAME)

이름이 실물과 어긋나 있었다 — `bastion host` 의 정의는 *인바운드를 받아 안쪽으로 전달*인데
이 모듈은 **인바운드 규칙이 0개**다. 요새가 아니라 **도구가 갖춰진 작업대**다.
근거 전문은 모듈 repo `docs/design/40-workbench.md §2.0`.

- ⛔ **구 태그 `bastion-v0.1.0` 은 원격에서 삭제됐다.** 그 핀으로 되돌리면 `init` 이 실패한다.
- ⏱️ **apply 전이라 공짜였다.** `purpose` 는 태그가 아니라 **식별자**로 흘러간다
  (`aws_iam_role.name` · `aws_iam_instance_profile.name` · `aws_security_group.name`) —
  apply 후였다면 그 셋이 replace 되고 Access Entry·cluster SG rule 까지 연쇄 replace 됐다.
  🔑 일반화: *"purpose·naming 토큰을 바꾸는 개명은 apply 전에만 공짜다."*
- ✅ **판정**: 개명 후 plan 이 **개명 전과 숫자가 같다.**
  [`31056930396`](https://github.com/skax-ca/iac-reference-infra/actions/runs/31056930396)(개명 전) ·
  [`31058277158`](https://github.com/skax-ca/iac-reference-infra/actions/runs/31058277158)(개명 후)
  둘 다 **`Plan: 10 to add, 0 to change, 0 to destroy`**. Name 도 `-workbench-01` 로 확인.

### ✅ apply·도달 실증 완료 (2026-08-06)

run [`31059712680`](https://github.com/skax-ca/iac-reference-infra/actions/runs/31059712680)
= **`Apply complete! Resources: 10 added, 0 changed, 0 destroyed.`** 인스턴스 `i-04ac14a6f5891492c`.

✅ **실계정 조회로 대조했다** — 이 repo 판정 기준은 apply 로그가 아니라 실물이다:

| 계약 | 실물 |
|------|------|
| 배치 | `ap-northeast-2c` · `subnet-074f0b4094109f277`(vm-uniq) · `10.51.20.186` |
| ⭐ 공인 IP 미할당 | `PublicIpAddress: null` |
| ⭐ 키페어 미지정 | `KeyName: null` |
| ⭐ **인바운드 0개** | `length(IpPermissions) == 0` · egress 는 443/tcp 하나 |
| 아키텍처 정합 | `t4g.nano` + `ami-0973292651cddee46`(AL2023 arm64) 부팅 성공 |

⭐ 3개는 모듈 repo `40 §5.1` 이 *"`tofu test` 로 지킬 수 없다"* 고 적은 항목이다
(*"미지정 자체가 계약"* 인데 plan 에선 `known after apply`). **여기서 처음 실증됐고
모듈 repo `40 §7.3-1` 에 기록했다.**

**도달 3층 전부 성립**:
```
SSM 등록      PingStatus: Online · agent 3.3.4851.0 · AL2023
cloud-init    status: done                     ← 비동기라 kubectl 확인 전에 먼저 본다
1층           /etc/kubernetes/kubeconfig 생성됨(2447B)
kubectl       Client Version: v1.35.7          ← 클러스터 1.35 와 마이너 일치
2·3층         kubectl get nodes → 노드 2개 Ready
```
🔑 **`get nodes` 가 반환된 것 자체가 3층 전부의 증거다.** 실패했다면 층별로 다른 에러가 났다.

⚠️ **판정 방식**: 대화형 `start-session` 이 아니라 **`ssm send-command`**(AWS-RunShellScript)다
— 자동화 환경에 TTY 가 없다. 같은 채널·IAM·SG 를 지나므로 도달성으로는 동등하다.
사람이 붙을 때: `aws ssm start-session --profile team --region ap-northeast-2 --target i-04ac14a6f5891492c`

### 🔴 다음 태스크 — **④ `endpoint_public_access = false` 로 닫고 재확인**

**이것이 `40 §1` 이 말한 이 설계의 목적이다.** 지금까지는 전부 선행 조건이었다.

> ⚠️ **지금 실증은 public 이 켜진 채로 났다.** 엄밀히는 *"private 경로로 닿았다"* 를 아직
> 증명하지 않았다 — public 을 통해 닿고 있었을 가능성이 남아 있다. **닫고 재확인하는 것이
> 그 배제의 유일한 방법**이고, 그래서 ④가 판정이다.

작업 목록(`live/dev/eks`):
- `main.tf` — `endpoint_public_access = false`, `public_access_cidrs` 줄 제거,
  그 자리 "🔴 아직 켜 둔다" 주석을 **닫은 근거로 교체**(죽은 주석을 남기지 않는다)
- `variables.tf` — `var.public_access_cidrs` **삭제**. ⚠️ tflint `terraform_unused_declarations`
  가 미사용 변수를 exit 2 로 잡으므로 **같은 커밋에서** 지운다
- repo 변수 `EKS_PUBLIC_ACCESS_CIDRS` 정리(코드가 안 쓰면 죽은 설정)
- `README.md §3` 형상표 엔드포인트 행 → **private-only**
- apply 후 **workbench 에서 `kubectl get nodes` 재확인** ← 판정

⚠️ 실패하면 되돌릴 방법이 workbench 뿐이다. 그래서 ①~③ 을 먼저 했다.

⚠️ **apply 는 사람이 `Run workflow` 를 누르는 것이 승인 게이트다**(D30-1). merge 만으로는 안 돈다.

## 미결 항목

- ✅ **해결** — EBS `volume_tags` drift → `providers.tf` `ignore_tags` 에 `Dependency*` 추가(PR #18)
- ✅ **해결** — repo 변수 `EKS_PUBLIC_ACCESS_CIDRS` 삭제 완료

- ✅ **#1 해결** — plan/apply 권한 분리 → C안(현재 구조 유지 + 문서화). `deployment-facts.md` §7
- ✅ **#4 해결** — CI `init` shallow clone → `&depth=1` 추가. `deployment-facts.md` §8
- ✅ **deepinit 실행 완료** (2026-08-04) — 9개 AGENTS.md 작성/hierarchical 검증 완료
- ✅ **plan artifact 암호화** — 문서화 완료 (2026-08-04). `retention-days: 1` 유지. 완전한 해결은 GitHub Free 구조와 상충 — artifact 없으면 승인 plan ≠ 적용 plan 구멍, artifact 있으면 repo read 권한자 접근 1일 제한. 현재 구조 유지(문서化는 deployment-facts.md §6 참고)

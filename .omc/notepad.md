# Notepad — iac-reference-infra

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

### ⏸ Phase 1 잔여 = **GitHub App 생성** (사용자 작업, 브라우저 전용)

⚠️ **API로 만들 수 없다** — `POST /orgs/{org}/apps`는 없고 manifest 변환은 브라우저 `code`를 요구한다(실측).

생성 URL: `https://github.com/organizations/skax-ca/settings/apps/new`

| 항목 | 값 |
|------|-----|
| 이름 | `skax-ca-module-reader` (임의, org 내 고유) |
| Homepage URL | `https://github.com/skax-ca/iac-module-library` (형식상 필수) |
| Webhook | **Active 체크 해제** |
| Repository permissions | **Contents: Read-only** — 이것 하나만 |
| Where can this be installed | **Only on this account** |
| 설치 후 | Install App → **Only select repositories** → `iac-module-library` **1개만** |

산출물 2개를 이 repo에 넣는다:
```bash
gh variable set MODULE_READER_APP_ID --repo skax-ca/iac-reference-infra --body '<App ID>'
gh secret   set MODULE_READER_KEY    --repo skax-ca/iac-reference-infra < <다운로드한 .pem>
```
⚠️ `.pem`은 repo 안에 두지 않는다(`.gitignore`가 `*.pem`을 막지만 애초에 넣지 않는다).

### ⏭️ 이후 Phase (의존 순서가 중요하다 — 닭-달걀 2차)

```
2 sub claim 실측(AWS 무관) → 3 bootstrap.sh → 4 apply → 5 모듈 repo docs/consumer/* 개정
                  ↑
   신뢰 정책은 sub를 알아야 하고, sub는 repo+워크플로가 있어야 나온다
```

**Phase 2** — throwaway 워크플로가 **3개 job**의 JWT claim을 출력한다:
`pull_request` / `push`→main / `environment: dev`. ⚠️ **plan job과 apply job의 sub가 다르다**(D28) —
`environment:`를 선언한 job만 `:environment:`를 받는다 → 신뢰 정책 **3패턴**.
예상(추정): `repo:skax-ca@310520211/iac-reference-infra@1316830050:...` — **추정이다. 실측 후 확정.**
측정법: `id-token: write` + `$ACTIONS_ID_TOKEN_REQUEST_URL`에서 JWT 받아 payload 디코드.
실측 후 워크플로 **삭제**(커밋으로).

**Phase 3** — `bootstrap.sh`(멱등) + `verify.sh`(read-only) + `README.md`(기대 상태 + import 초안).
⚠️ 완화책 4종은 **수용 기준**이다. `verify.sh`는 **음성 테스트로 실제로 잡는지 증명**해야 한다.
⚠️ **D29**: 버저닝 + `use_lockfile` → lock 객체 버전 폭증(공식 경고) → **lifecycle 필수**.
⚠️ **D27**: `AWSAFTExecution` 신뢰 정책 principal이 unique ID로 치환돼 **assume 불가** →
`update-assume-role-policy`로 **전체 교체**.

**Phase 4** — `live/dev/networking/` + `deploy.yml`(**한 run 두 job**: plan → 승인 → `tofu apply tfplan`).
쪼개면 "승인한 계획 ≠ 적용된 계획" 구멍이 열린다. `concurrency` 필수.

### ⚠️ 과잉 주장 금지

첫 apply가 판정하는 것은 모듈 미검증 6항목 중 **6번(git tag 소싱)과 minimal 경로뿐**이다.
secondary CIDR·CIDR 겹침·Flow Logs 배달·`prevent_destroy`는 **후속 시나리오**다.
추가 판정 기준: **두 번째 apply가 `No changes`인가**(가짜 diff = `ignore_tags` 필요 여부).

## 미결 항목

- plan/apply 권한 분리 — `tofu plan`도 state lock을 잡아 "plan은 read-only"가 성립하지 않는다(D28)
- CI `init`이 모듈 repo **전체를 clone**한다(실측). 태그·히스토리 증가 시 `?depth=1` 검토
- plan artifact 암호화 — `retention-days: 1`은 완화이지 해결이 아니다
- deepinit은 **Phase 4 이후**에 돌린다 — 지금은 `.tf`가 없어 분석 대상이 없다

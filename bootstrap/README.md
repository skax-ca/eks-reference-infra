# bootstrap — 부트스트랩 (IaC 밖, D21)

state 버킷·OIDC provider·2단 Role을 **AWS CLI 스크립트로** 만든다.
`tofu`가 이것들을 만들려면 이미 state 버킷이 있어야 하므로(닭-달걀), 이 한 겹만 IaC 밖에 둔다.

> ⛔ **대가가 있다.** drift 감지·변경 이력·IaC 자산성을 잃는다. 그래서 아래 4개는 선택이 아니라
> **요건**이다(모듈 repo `design/50` D21). 이 README의 **§2 표가 `.tf`를 대체하는 SSOT**다.

| 요건 | 이행 | 증명 |
|------|------|------|
| 멱등성 | 항목마다 검사 후 다를 때만 적용 | §4-1 |
| 기대 상태 명문화 | **§2 표** | — |
| drift 감지 대체 | `verify.sh` (read-only) | §4-2 **음성 테스트** |
| IaC 승격 경로 | **§5** `import` 초안 | — |

---

## 1. 실행

```bash
./bootstrap.sh      # 생성·수렴 (AWS_PROFILE 기본 team)
./verify.sh         # drift 확인만 (read-only). exit 0=일치 / 1=drift / 2=실행 불가
```

- ⚠️ **대상 계정은 공용 개발 계정이다**(`CLAUDE.md` §4-1). 스크립트는 계정 ID를 검증하고
  다르면 즉시 중단한다 — 조용히 다른 계정을 치지 않게 하는 장치다.
- ⛔ **`AWSAFTExecution`을 건드리지 않는다**(D27-1). `update-assume-role-policy`가
  이 디렉토리에서 그 Role을 향하면 규약 위반이다.
- 스크립트는 **bash 전용**이다(`config.sh`가 bash 배열을 쓴다). zsh에서 `source` 하지 않는다.

## 2. 기대 상태 (SSOT)

`config.sh`가 코드 측면, 이 표가 문서 측면이다. **어긋나면 이 표를 고친다.**

### S3 state 버킷

| 항목 | 기대값 | 근거 |
|------|--------|------|
| 이름 | `s3-ref-dev-an2-tfstate-<guid12>` | 네이밍 규약 + AWS가 예측 불가능한 이름을 권장(F12) |
| **이름의 소재** | **git에 없다.** 실물은 GitHub repo 변수 `TF_STATE_BUCKET` / 로컬 `backend.hcl` | **D25** |
| 버저닝 | `Enabled` | state 손상 복구 |
| 암호화 | `AES256` (SSE-S3, BucketKey on) | 기본값이지만 명시적으로 검사한다 |
| 퍼블릭 차단 | 4개 전부 `true` | |
| **lifecycle** | 비현행 버전 **7일** · 불완전 MPU **7일** | **D29** — `use_lockfile=true`가 lock 객체 버전을 폭증시킨다(F8, 공식 경고) |
| 태그 | `Name` `Workload=ref` `Environment=dev` `ManagedBy=bootstrap.sh` `Owner` `CostCenter` | IaC 밖이라 `default_tags`가 없다 → 스크립트가 직접 붙인다 |

### OIDC provider

| 항목 | 기대값 |
|------|--------|
| URL | `token.actions.githubusercontent.com` |
| client ID (`aud`) | `sts.amazonaws.com` |
| thumbprint | **설정하지 않는다** — CLI에서 선택 인자임을 실측 확인했고, AWS가 2023년부터 알려진 IdP를 자체 신뢰 저장소로 검증한다. 지문을 박으면 만료 부채만 남는다 |
| `Name` 태그 | `iamoidc-ref-dev-an2-gha` |

> ⚠️ 이 리소스는 **식별자가 URL**이라 `name` 인자가 없다 → 이름은 **`Name` 태그로만** 표현된다.

### IAM Role 2단 (D27-1)

| Role | 신뢰 | 권한 |
|------|------|------|
| **입구** `iamr-ref-dev-an2-gha-entry-01` | OIDC provider + `aud` + **`sub` 3패턴** | inline `…-policy`: 실행 Role `sts:AssumeRole` **하나뿐** |
| **실행** `iamr-ref-dev-an2-gha-exec-01` | **입구 Role만** (계정 루트 아님) | `AdministratorAccess` |

`sub` 3패턴 (Phase 2 실측 — `docs/deployment-facts.md` §3):

```
repo:skax-ca@310520211/iac-reference-infra@1316830050:pull_request
repo:skax-ca@310520211/iac-reference-infra@1316830050:ref:refs/heads/main
repo:skax-ca@310520211/iac-reference-infra@1316830050:environment:dev
```

- ⚠️ **`environment`를 선언한 job만 `:environment:`를 받는다**(D28). 하나로 뭉칠 수 없다.
- ⛔ **와일드카드로 넓히지 않는다.** `repo:…*`로 쓰면 org 내 **다른 repo**가 이 Role을 assume한다.
- 실행 Role의 신뢰를 계정 루트(`arn:aws:iam::<acct>:root`)로 두면 **계정 내 누구나** assume할 수
  있다. 공용 계정이므로 특히 안 된다 — 입구 Role 하나로 못박는다.

## 3. 순서가 자유롭지 않다 (실측)

```
① OIDC provider  →  ② 입구 Role(신뢰=①)  →  ③ 실행 Role(신뢰=②)  →  ④ 입구 inline 정책(Resource=③)
```

- **IAM은 신뢰 정책의 principal이 실제로 존재하는지 검증한다.** 아직 없는 Role을 principal로 쓰면
  `MalformedPolicyDocument: Invalid principal in policy`다.
  → "ARN은 결정적이니 계산해서 상호 참조를 끊는다"는 접근은 **동작하지 않는다**(실측으로 반증).
- ④가 마지막이어도 되는 이유: **`Resource`는 principal이 아니라 존재 검증을 받지 않는다.**
  이 비대칭이 순환을 푸는 지점이다.
- ⚠️ **IAM은 eventual consistency다.** ②를 만든 **직후** ③을 만들면 방금 만든 Role이 아직 안 보여
  같은 오류가 난다. `bootstrap.sh`는 `Invalid principal`일 때만 5초 간격으로 최대 10회 재시도한다.
  이 재시도가 없으면 첫 실행은 반드시 실패하고 두 번째에만 성공한다 —
  **멱등성이 실패를 가려주는 상태**이고, 그건 수렴이 아니라 운이다.

## 4. 검증 기록 (2026-07-30 실측)

### 4-1. 멱등성

```
1회차: 변경 6건 (버킷·버저닝·lifecycle·OIDC·Role 2개·정책)
2회차: 변경 0건  → "이미 기대 상태다 (멱등 확인)"
```

### 4-2. 음성 테스트 — `verify.sh`가 **실제로 잡는지** 증명

완화책이 있다고 주장하려면 그것이 동작함을 보여야 한다. 다음을 실행해 재현한다.

```bash
source ./config.sh; B="$(find_bucket)"        # ⚠️ bash 로 실행할 것

# drift 주입 — 서로 다른 코드 경로 2개(S3 · IAM)
aws_ s3api put-bucket-versioning --bucket "$B" --versioning-configuration Status=Suspended
aws_ iam put-role-policy --role-name "$ENTRY_ROLE" --policy-name "$ENTRY_POLICY" \
  --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":"sts:AssumeRole","Resource":"*"}]}'

./verify.sh     # → DRIFT 2건, exit 1
./bootstrap.sh  # → 변경 2건 (그 2개만. 나머지는 ok)
./verify.sh     # → drift 없음, exit 0
./bootstrap.sh  # → 변경 0건
```

**실측 결과**: 위 순서대로 정확히 나왔다. `verify.sh`는 소음이 아니라 실제 탐지기다.

- 부트스트랩 **이전**에도 검증했다: 아무것도 없는 상태에서 **6건 전부 `absent`로 잡고 exit 1**.

## 5. IaC 승격 경로 (`import` 초안)

지금 올리지 않는다(§5 열린 항목, D21). 올릴 때 처음부터 다시 설계하지 않도록 초안만 둔다.

```hcl
# ⚠️ 버킷명은 git 에 없다(D25) → var 로 받는다. 값을 여기 적으면 D25 가 무의미해진다.
variable "state_bucket" { type = string }

import {
  to = aws_s3_bucket.tfstate
  id = var.state_bucket
}
import {
  to = aws_iam_openid_connect_provider.gha
  id = "arn:aws:iam::${var.account_id}:oidc-provider/token.actions.githubusercontent.com"
}
import {
  to = aws_iam_role.gha_entry
  id = "iamr-ref-dev-an2-gha-entry-01"
}
import {
  to = aws_iam_role.gha_exec
  id = "iamr-ref-dev-an2-gha-exec-01"
}
import {
  to = aws_iam_role_policy.gha_entry          # inline 정책
  id = "iamr-ref-dev-an2-gha-entry-01:iamr-ref-dev-an2-gha-entry-01-policy"
}
```

⚠️ **승격의 진짜 문제는 import 문법이 아니다.** state 버킷을 관리하는 루트의 state를
**그 버킷 자신에** 두면 파괴 시 자기 발을 쏜다. 승격 시 별도 backend 또는
`prevent_destroy`를 함께 설계해야 한다 — 그래서 "지금 올리지 않는다"가 결정이다.

## 6. 출력값의 행선지

`bootstrap.sh`가 마지막에 출력한다. **어느 것도 git에 커밋하지 않는다**(D25 확장).

| 값 | 행선지 |
|----|--------|
| `TF_STATE_BUCKET` | GitHub repo 변수 |
| `AWS_ENTRY_ROLE_ARN` · `AWS_EXEC_ROLE_ARN` | GitHub repo 변수 |
| 로컬 `backend.hcl` | **gitignore 됨.** `tofu init -backend-config=backend.hcl` |

`docs/deployment-facts.md`는 **값이 아니라 "어디에 있는지"** 를 기록한다.

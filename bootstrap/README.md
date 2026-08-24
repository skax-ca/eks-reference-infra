# bootstrap — 부트스트랩 (IaC 밖)

**읽는 사람**: 부트스트랩 스크립트를 실행하거나 고치는 사람.

state 버킷·OIDC provider·2단 Role을 **AWS CLI 스크립트로** 만든다.
`tofu`가 이것들을 만들려면 이미 state 버킷이 있어야 하므로(닭-달걀), 이 한 겹만 IaC 밖에 둔다.

> ⛔ **대가가 있다.** drift 감지·변경 이력·IaC 자산성을 잃는다. 그래서 아래 4개는 선택이 아니라
> **요건**이다(근거는 `iac-module-library`의 `docs/`가 소유한다). 이 README의
> **「2. 기대 상태 (SSOT)」 표가 `.tf`를 대체하는 SSOT**다.

| 요건 | 이행 | 증명 |
|------|------|------|
| 멱등성 | 항목마다 검사 후 다를 때만 적용 | 「4-1. 멱등성」 |
| 기대 상태 명문화 | **「2. 기대 상태 (SSOT)」 표** | — |
| drift 감지 대체 | `verify.sh` (read-only) | 「4-2. 음성 테스트」 |
| IaC 승격 경로 | **「5. IaC 승격 경로」** `import` 초안 | — |

---

## 1. 실행

```bash
export EXPECTED_ACCOUNT=<12자리 계정 ID>   # ⛔ 필수. 기본값이 없다 (아래)

./bootstrap.sh      # 생성·수렴 (BOOTSTRAP_TARGET 기본 hub, AWS_PROFILE 기본 team)
./verify.sh         # drift 확인만 (read-only). exit 0=일치 / 1=drift / 2=실행 불가
```

spoke 계정은 대상과 환경 토큰을 명시한다. 첫 spoke 인스턴스는 `dev`다.

```bash
BOOTSTRAP_TARGET=spoke SPOKE_ENV=dev AWS_PROFILE=asset \
  EXPECTED_ACCOUNT=<asset 계정 ID> ./bootstrap.sh

BOOTSTRAP_TARGET=spoke SPOKE_ENV=dev AWS_PROFILE=asset \
  EXPECTED_ACCOUNT=<asset 계정 ID> ./verify.sh
```

- ⛔ **`EXPECTED_ACCOUNT`에 기본값을 두지 않는다** — 계정 ID는 git에 남기지 않는다.
  미설정이면 스크립트가 **즉시 중단**한다. 값의 소재는 `docs/deployment-facts.md`가 가리킨다.
  - 이 값은 **검증에만 쓰이는 것이 아니다.** `oidc_arn()`·`role_arn()`이 ARN을 조립할 때
    소비하므로, 빠지면 부트스트랩 전체가 성립하지 않는다.
  - ⛔ *"해시로 저장해 비교하면 되지 않나"* 는 **이미 기각된 안**이다 — 계정 ID 공간이
    10¹²뿐이라 전수 해싱이 가능하다. **해시가 보호가 되지 않는다.**
- ⚠️ **대상 계정은 실행마다 명시한다.** hub는 team 계정, spoke:dev는 asset 계정이다.
  스크립트는 `sts get-caller-identity`로 실제 계정과 `EXPECTED_ACCOUNT`를 대조하고 다르면 즉시
  중단한다 — 조용히 다른 계정을 치지 않게 하는 장치다. **필수 주입이 된 덕에 실행자가 매번 대상을
  명시하게 되므로 이 방어가 강해졌다.**
- ⛔ **`AWSAFTExecution`을 건드리지 않는다.** `update-assume-role-policy`가
  이 디렉토리에서 그 Role을 향하면 규약 위반이다.
- 스크립트는 **bash 전용**이다(`config.sh`가 bash 배열을 쓴다). zsh에서 `source` 하지 않는다.

## 2. 기대 상태 (SSOT)

`config.sh`가 코드 측면, 이 표가 문서 측면이다. **어긋나면 이 표를 고친다.**

> **hub는 team 계정의 단일 고정 거처이고, spoke는 별도 계정에 놓이는 여러 인스턴스다.** 첫 spoke
> 인스턴스의 env 토큰은 `dev`다. `spoke`는 새 네이밍 토큰이 아니라 역할이므로, 이름에는
> `SPOKE_ENV` 값(`dev`, 향후 `stage` 등)을 쓴다.
> **OIDC provider는 계정마다 URL당 1개**만 만들 수 있다. hub와 spoke는 서로 다른 계정이므로 공유하지
> 않고, 각 계정 안에서 하나씩 가진다.

### S3 state 버킷 (target별 1개)

| 항목 | hub | spoke (`SPOKE_ENV=dev`) |
|------|-----|-------------------------|
| 실행 대상 | `BOOTSTRAP_TARGET=hub` (기본값) | `BOOTSTRAP_TARGET=spoke SPOKE_ENV=dev` |
| 계정 | team 계정 | asset 계정 |
| 이름 | `s3-demo-hub-an2-tfstate-<guid12>` | `s3-demo-dev-an2-tfstate-<guid12>` |
| **이름의 소재** | **git에 없다.** GitHub repo 변수 `HUB_TF_STATE_BUCKET` / 로컬 `backend.hcl` | 같은 방식, `DEV_TF_STATE_BUCKET` |
| 태그 `Environment` | `hub` | `dev` |

공통(둘 다 동일): 버저닝 `Enabled`(state 손상 복구) · 암호화 `AES256`(SSE-S3, BucketKey on) ·
퍼블릭 차단 4개 전부 `true` · **lifecycle** 비현행 버전 **7일**·불완전 MPU **7일**
(`use_lockfile=true`가 lock 객체 버전을 폭증시킨다, AWS 공식 경고) · 태그 `Name`·`Workload=demo`·
`ManagedBy=bootstrap.sh`·`Owner`·`CostCenter`(IaC 밖이라 `default_tags`가 없다 → 스크립트가 직접 붙인다).

### OIDC provider (각 계정에 1개 — AWS 제약)

| 항목 | 기대값 |
|------|--------|
| URL | `token.actions.githubusercontent.com` |
| client ID (`aud`) | `sts.amazonaws.com` |
| thumbprint | **설정하지 않는다** — CLI에서 선택 인자임을 실측 확인했고, AWS가 2023년부터 알려진 IdP를 자체 신뢰 저장소로 검증한다. 지문을 박으면 만료 부채만 남는다 |
| `Name` 태그 | `iamoidc-demo-an2-gha`(env 토큰 없음 — 계정 레벨 자원이라는 뜻을 반영) |

> ⚠️ 이 리소스는 **식별자가 URL**이라 `name` 인자가 없다 → 이름은 **`Name` 태그로만** 표현된다.
> ⚠️ AWS가 URL당 계정에 정확히 1개만 허용한다. 같은 계정 안에서 두 target이 공존하면 나눌 수
> 없지만, 현재 hub(team)와 spoke(asset)는 계정이 달라 각자 1개씩 만든다.

### IAM Role 2단 (target별 1세트)

| Role | 신뢰 | 권한 |
|------|------|------|
| **[hub] 입구** `iamr-demo-hub-an2-gha-entry-01` | OIDC provider + `aud` + **`sub` 2패턴**(아래) | inline: hub 실행 Role `sts:AssumeRole` **하나뿐** |
| **[hub] 실행** `iamr-demo-hub-an2-gha-exec-01` | **hub 입구 Role만** | `AdministratorAccess` |
| **[spoke:dev] 입구** `iamr-demo-dev-an2-gha-entry-01` | OIDC provider + `aud` + **`sub` 2패턴**(아래) | inline: spoke 실행 Role `sts:AssumeRole` **하나뿐** |
| **[spoke:dev] 실행** `iamr-demo-dev-an2-gha-exec-01` | **spoke:dev 입구 Role만** | `AdministratorAccess` |

hub `sub` 2패턴 — `pull_request`가 없다: hub workflow는 애초에 PR 트리거가 없다(`CLAUDE.md`
「4」) — 쓰이지 않는 패턴을 만들어 두지 않는다:

```
repo:skax-ca@310520211/eks-reference-infra@1316830050:ref:refs/heads/main
repo:skax-ca@310520211/eks-reference-infra@1316830050:environment:hub
```

spoke `sub` 2패턴 — `environment:` 값은 `SPOKE_ENV`다. `SPOKE_ENV=dev`일 때:

```
repo:skax-ca@310520211/eks-reference-infra@1316830050:ref:refs/heads/main
repo:skax-ca@310520211/eks-reference-infra@1316830050:environment:dev
```

> `ref:refs/heads/main` 값은 hub·spoke가 **동일**하다 — 같은 repo·브랜치라 sub가 env가 아니라
> ref로 갈리기 때문이다. 그래도 Role 자체는 각 target 계정 안에서 따로 소유한다.

- ⚠️ **`environment`를 선언한 job만 `:environment:`를 받는다.** 하나로 뭉칠 수 없다.
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

## 4. 검증 기록

### 4-1. 멱등성

재실행 시 이미 존재하는 항목은 전부 `ok`로 표시되고 `=== 변경 0건 ===`·"이미 기대 상태다"가
출력되어야 한다 — 그렇지 않으면 `check_*` 함수와 실제 AWS 상태가 어긋난 것이다.

⚠️ **로그를 찍으면서 값도 `$(...)`로 반환하는 함수(예: `converge_bucket()`)를 추가할 때는
`ok()`/`changed()`가 stderr로 나가는지 확인한다** — stdout으로 나가면 반환값에 로그 텍스트가
섞여 깨진다. `$(...)`는 서브셸이라 그 안에서의 `CHANGES` 카운터 증가도 상위 셸에 반영되지
않는다는 점도 함께 주의한다 — 카운터가 과소 표시될 수 있다.

### 4-2. 음성 테스트 — `verify.sh`가 **실제로 잡는지** 증명

완화책이 있다고 주장하려면 그것이 동작함을 보여야 한다. 다음을 실행해 재현한다.

```bash
source ./config.sh; B="$(find_hub_bucket)"        # ⚠️ bash 로 실행할 것

# drift 주입 — 서로 다른 코드 경로 2개(S3 · IAM)
aws_ s3api put-bucket-versioning --bucket "$B" --versioning-configuration Status=Suspended
aws_ iam put-role-policy --role-name "$HUB_ENTRY_ROLE" --policy-name "$HUB_ENTRY_POLICY" \
  --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":"sts:AssumeRole","Resource":"*"}]}'

./verify.sh     # → DRIFT 2건, exit 1
./bootstrap.sh  # → 변경 2건 (그 2개만. 나머지는 ok)
./verify.sh     # → drift 없음, exit 0
./bootstrap.sh  # → 변경 0건
```

**실측 결과**: 위 순서대로 정확히 나왔다. `verify.sh`는 소음이 아니라 실제 탐지기다.

- 부트스트랩 **이전**에도 검증했다: 아무것도 없는 상태에서 **6건 전부 `absent`로 잡고 exit 1**.

## 5. IaC 승격 경로 (`import` 초안)

지금 올리지 않는다(이 절 자체가 열린 항목이다). 올릴 때 처음부터 다시 설계하지 않도록 초안만 둔다.

```hcl
# ⚠️ 버킷명은 git 에 없다 → var 로 받는다. 값을 여기 적으면 그 요건이 무의미해진다.
variable "state_bucket" { type = string }
variable "env" { type = string } # 예: hub 또는 dev

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
  id = "iamr-demo-${var.env}-an2-gha-entry-01"
}
import {
  to = aws_iam_role.gha_exec
  id = "iamr-demo-${var.env}-an2-gha-exec-01"
}
import {
  to = aws_iam_role_policy.gha_entry          # inline 정책
  id = "iamr-demo-${var.env}-an2-gha-entry-01:iamr-demo-${var.env}-an2-gha-entry-01-policy"
}
```

⚠️ **승격의 진짜 문제는 import 문법이 아니다.** state 버킷을 관리하는 루트의 state를
**그 버킷 자신에** 두면 파괴 시 자기 발을 쏜다. 승격 시 별도 backend 또는
`prevent_destroy`를 함께 설계해야 한다 — 그래서 "지금 올리지 않는다"가 결정이다.

## 6. 출력값의 행선지

`bootstrap.sh`가 마지막에 출력한다. **어느 것도 git에 커밋하지 않는다** — 계정 식별 정보를
git에 두지 않는다는 요건의 연장이다.

| 값 | 행선지 |
|----|--------|
| `HUB_TF_STATE_BUCKET`(hub) | GitHub repo 변수 |
| `HUB_AWS_ENTRY_ROLE_ARN`·`HUB_AWS_EXEC_ROLE_ARN`(hub) | GitHub repo 변수 |
| `DEV_TF_STATE_BUCKET`(spoke:dev) | GitHub repo 변수 |
| `DEV_AWS_ENTRY_ROLE_ARN`·`DEV_AWS_EXEC_ROLE_ARN`(spoke:dev) | GitHub repo 변수 |
| 로컬 `backend.hcl`(각 루트 디렉토리) | **gitignore 됨.** `tofu init -backend-config=backend.hcl` |

기존 무접두 `TF_STATE_BUCKET`·`AWS_ENTRY_ROLE_ARN`·`AWS_EXEC_ROLE_ARN` repo 변수는 삭제 대상이다.
`SPOKE_ENV=dev`가 아닌 spoke 인스턴스는 아직 워크플로 배선(repo 변수 이름·`live/<env>/` 루트)이
없다. 또한 `DEV_*` 같은 env prefix 만으로는 같은 env 안의 다중 클러스터를 표현할 수 없으므로,
실제 CI에 연결하려면 별도 설계가 먼저 필요하다.

`docs/deployment-facts.md`는 **값이 아니라 "어디에 있는지"** 를 기록한다.

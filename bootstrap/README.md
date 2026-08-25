# bootstrap: 부트스트랩 (IaC 밖)

**읽는 사람**: 부트스트랩 스크립트를 처음 실행하거나 고치는 사람.

state 버킷, OIDC provider, 2단 IAM Role을 AWS CLI 스크립트로 만든다. `tofu`가 이것들을
만들려면 이미 state 버킷이 있어야 하는 닭과 달걀 문제가 있어서, 이 한 겹만 IaC 밖에 둔다.

IaC 밖에 두면 잃는 것이 있다. drift 감지, 변경 이력, 리소스를 코드로 다시 만들 수 있다는
보장, 이 세 가지가 사라진다. 그래서 아래 표의 네 가지를 대체 수단으로 갖춘다.

| 잃는 것 | 대체 수단 |
|------|------|
| 기대 상태가 코드로 안 남는다 | 아래 「2. 기대 상태」 표가 사람이 읽는 SSOT다 |
| drift 감지가 안 된다 | `verify.sh` (읽기 전용) |
| 멱등하게 재실행된다는 보장이 코드로 안 남는다 | 「3. 검증」의 재실행·음성 테스트로 증명한다 |
| 코드로 승격할 길이 안 보인다 | 「4. IaC 승격 경로」에 `import` 초안을 남긴다 |

---

## 1. 실행

```bash
export EXPECTED_ACCOUNT=<12자리 계정 ID>   # 필수. 기본값이 없다

cd bootstrap
./bootstrap.sh      # 생성·수렴 (BOOTSTRAP_TARGET 기본 hub, AWS_PROFILE 기본 team)
./verify.sh         # drift 확인만 (읽기 전용). exit 0=일치 / 1=drift / 2=실행 불가
```

spoke 계정은 대상과 환경 토큰을 명시한다. 첫 spoke 인스턴스는 `dev`다.

```bash
BOOTSTRAP_TARGET=spoke SPOKE_ENV=dev AWS_PROFILE=asset \
  EXPECTED_ACCOUNT=<asset 계정 ID> ./bootstrap.sh

BOOTSTRAP_TARGET=spoke SPOKE_ENV=dev AWS_PROFILE=asset \
  EXPECTED_ACCOUNT=<asset 계정 ID> ./verify.sh
```

⛔ **`EXPECTED_ACCOUNT`에 기본값을 두지 않는다.** 계정 ID는 git에 남기지 않는다. 값은 AWS
계정 관리자에게 확인한다. 미설정이면 스크립트가 즉시 중단한다(`exit 2`, drift가 아니라
실행 불가로 분류된다).

⚠️ **대상 계정은 실행마다 명시한다.** hub는 team 계정, spoke:dev는 asset 계정이다.
스크립트가 `sts get-caller-identity`로 실제 계정과 `EXPECTED_ACCOUNT`를 대조하고 다르면
즉시 중단한다. 공용 계정에서 조용히 다른 계정을 건드리지 않게 하는 장치다.

⚠️ 스크립트는 bash 전용이다(`config.sh`가 배열 인덱싱을 쓴다). zsh에서 `source`하지 않는다.

---

## 2. 기대 상태

`config.sh`가 코드 측면이고 이 표가 문서 측면이다. **둘이 어긋나면 이 표를 고친다.** 사람이
읽는 쪽을 SSOT로 둔 이유는, 코드 주석만으로는 "지금 실제로 뭐가 만들어져 있어야 하는가"를
한눈에 확인하기 어렵기 때문이다.

hub는 team 계정의 단일 고정 거처이고, spoke는 별도 계정에 놓이는 여러 인스턴스다. 첫 spoke
인스턴스의 환경 토큰은 `dev`다. OIDC provider는 계정마다 URL당 1개만 만들 수 있어서, hub와
spoke가 서로 다른 계정인 이 구조에서는 자연히 하나씩 갖는다.

### S3 state 버킷 (대상별 1개)

| 항목 | hub | spoke (`SPOKE_ENV=dev`) |
|------|-----|-------------------------|
| 실행 대상 | `BOOTSTRAP_TARGET=hub` (기본값) | `BOOTSTRAP_TARGET=spoke SPOKE_ENV=dev` |
| 계정 | team 계정 | asset 계정 |
| 이름 | `s3-demo-hub-an2-tfstate-<임의 12자>` | `s3-demo-dev-an2-tfstate-<임의 12자>` |
| 이름의 소재 | git에 없다. GitHub repo 변수 `HUB_TF_STATE_BUCKET` 또는 로컬 `backend.hcl` | 같은 방식, `DEV_TF_STATE_BUCKET` |
| 태그 `Environment` | `hub` | `dev` |

공통 설정(둘 다 동일): 버저닝 `Enabled`(state 손상 복구용), 암호화 `AES256`(SSE-S3,
BucketKey 활성), 퍼블릭 액세스 차단 4개 항목 전부 `true`, lifecycle 규칙으로 비현행 버전
7일·불완전 멀티파트 업로드 7일 후 정리(`use_lockfile = true`가 lock 객체 버전을 계속
쌓기 때문에 이 방어가 필요하다). 태그 `Name`·`Workload=demo`·`ManagedBy=bootstrap.sh`·
`Owner`·`CostCenter`도 붙는다(IaC 밖이라 provider의 `default_tags`가 적용되지 않아
스크립트가 직접 붙인다).

### OIDC provider (계정에 1개, AWS 제약)

| 항목 | 기대값 |
|------|--------|
| URL | `token.actions.githubusercontent.com` |
| client ID (`aud`) | `sts.amazonaws.com` |
| thumbprint | 설정하지 않는다. CLI에서 선택 인자이고, AWS가 알려진 IdP 인증서를 자체
신뢰 저장소로 검증한다. 지문을 박아 두면 인증서가 갱신될 때마다 손볼 부채만 남는다 |
| `Name` 태그 | `iamoidc-demo-an2-gha` (환경 토큰이 없다. 계정 레벨 자원이라는 뜻이다) |

⚠️ 이 리소스는 URL이 식별자라서 `name` 인자가 없다. 이름은 `Name` 태그로만 표현된다.

### IAM Role 2단 (대상별 1세트)

| Role | 신뢰 | 권한 |
|------|------|------|
| [hub] 입구 `iamr-demo-hub-an2-gha-entry-01` | OIDC provider + `aud` + `sub` 2패턴(아래) | inline: hub 실행 Role `sts:AssumeRole` 하나뿐 |
| [hub] 실행 `iamr-demo-hub-an2-gha-exec-01` | hub 입구 Role만 | `AdministratorAccess` |
| [spoke:dev] 입구 `iamr-demo-dev-an2-gha-entry-01` | OIDC provider + `aud` + `sub` 2패턴(아래) | inline: spoke 실행 Role `sts:AssumeRole` 하나뿐 |
| [spoke:dev] 실행 `iamr-demo-dev-an2-gha-exec-01` | spoke:dev 입구 Role만 | `AdministratorAccess` |

`sub` 조건은 두 패턴만 허용한다(`pull_request` 트리거가 없어 그 패턴은 만들지 않는다):

```
repo:skax-ca@310520211/eks-reference-infra@1316830050:ref:refs/heads/main
repo:skax-ca@310520211/eks-reference-infra@1316830050:environment:hub   # 또는 :environment:<SPOKE_ENV>
```

숫자 두 개는 GitHub 조직·저장소의 불변 ID다(`config.sh`의 `GH_ORG_ID`·`GH_REPO_ID`).
저장소 이름과 달리 rename에도 바뀌지 않는다.

`ref:refs/heads/main` 패턴은 hub와 spoke가 같은 값을 쓴다(같은 저장소·브랜치라 `sub`가
환경이 아니라 ref로 갈리기 때문이다). Role 자체는 각 target 계정 안에서 따로 소유한다.

⛔ 와일드카드로 넓히지 않는다. `repo:…*`로 쓰면 조직 내 다른 저장소가 이 Role을 assume할
수 있게 된다.
⛔ 실행 Role의 신뢰를 계정 루트(`arn:aws:iam::<acct>:root`)로 두지 않는다. 공용 계정에서는
계정 내 누구나 assume할 수 있게 되므로 특히 위험하다. 입구 Role 하나로만 좁힌다.

### 순서가 자유롭지 않다

```
① OIDC provider  →  ② 입구 Role(신뢰=①)  →  ③ 실행 Role(신뢰=②)  →  ④ 입구 inline 정책(Resource=③)
```

IAM은 신뢰 정책의 principal이 실제로 존재하는지 검증한다. 아직 없는 Role을 principal로
쓰면 `MalformedPolicyDocument: Invalid principal in policy`가 난다. ④가 마지막이어도 되는
이유는 `Resource`가 principal과 달리 존재 검증을 받지 않기 때문이다.

⚠️ IAM은 최종 일관성 모델이다. ②를 만든 직후 ③을 만들면 방금 만든 Role이 아직 안 보여
같은 오류가 날 수 있다. `bootstrap.sh`는 `Invalid principal` 오류일 때만 5초 간격으로
최대 10회 재시도한다. 이 재시도가 없으면 첫 실행은 반드시 실패하고 두 번째 실행에서만
성공한다. 그건 수렴이 아니라 운이다.

---

## 3. 검증

### 3-1. 멱등성

재실행하면 이미 있는 항목은 전부 `ok`로 표시되고 `=== 변경 0건 ===`이 출력되어야 한다.
그렇지 않으면 `check_*` 함수와 실제 AWS 상태가 어긋난 것이다.

### 3-2. 음성 테스트: verify.sh가 실제로 drift를 잡는지 증명한다

drift 감지가 있다고 주장하려면 그것이 동작하는 것을 직접 보여야 한다. 리소스를 일부러
어긋나게 만든 뒤 `exit 1`이 나오는지 확인하지 않으면 "완화책이 있다"는 착각만 남는다.

```bash
source ./config.sh; B="$(find_hub_bucket)"        # ⚠️ bash로 실행할 것

# drift 주입 — 서로 다른 코드 경로 2개 (S3 · IAM)
aws_ s3api put-bucket-versioning --bucket "$B" --versioning-configuration Status=Suspended
aws_ iam put-role-policy --role-name "$HUB_ENTRY_ROLE" --policy-name "$HUB_ENTRY_POLICY" \
  --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":"sts:AssumeRole","Resource":"*"}]}'

./verify.sh     # → DRIFT 2건, exit 1 이어야 한다
./bootstrap.sh  # → 변경 2건만 (나머지는 ok)
./verify.sh     # → drift 없음, exit 0
./bootstrap.sh  # → 변경 0건
```

이 순서대로 결과가 나오면 `verify.sh`는 소음이 아니라 실제 탐지기임이 증명된 것이다.
아무것도 없는 처음 상태에서 돌리면 6건 전부 `absent`로 잡고 `exit 1`이 나오는 것도
함께 확인한다.

---

## 4. IaC 승격 경로 (`import` 초안)

지금은 올리지 않는다. 올릴 때 처음부터 다시 설계하지 않도록 방향만 남긴다.

```hcl
variable "state_bucket" { type = string }  # 값을 여기 적지 않는다. 그러면 "버킷명이 git에
                                            # 없다"는 요건이 무의미해진다
variable "env"          { type = string }  # 예: hub 또는 dev

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
```

⚠️ 진짜 문제는 import 문법이 아니라, state 버킷을 관리하는 루트의 state를 그 버킷 자신에
두면 파괴 시 자기 발을 쏘게 된다는 점이다. 승격할 때는 별도 backend 또는
`prevent_destroy`를 함께 설계해야 한다. 지금 올리지 않는 이유가 이것이다.

---

## 5. 출력값의 행선지

`bootstrap.sh`가 실행 끝에 값을 출력한다. **어느 것도 git에 커밋하지 않는다.**

| 값 | 행선지 |
|----|--------|
| `HUB_TF_STATE_BUCKET`, `HUB_AWS_ENTRY_ROLE_ARN`, `HUB_AWS_EXEC_ROLE_ARN` (hub) | GitHub repo 변수 |
| `DEV_TF_STATE_BUCKET`, `DEV_AWS_ENTRY_ROLE_ARN`, `DEV_AWS_EXEC_ROLE_ARN` (spoke:dev) | GitHub repo 변수 |
| 로컬 `backend.hcl` (각 `live/<env>/` 디렉토리) | gitignore됨. `tofu init -backend-config=backend.hcl` |

새 spoke 인스턴스(`dev`가 아닌 환경)를 추가하면 워크플로 배선(repo 변수 이름, `live/<env>/`
루트)이 아직 없다. 그 배선은 이 부트스트랩과 별개로 설계해야 한다.

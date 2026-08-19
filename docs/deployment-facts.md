# 배포 사실 (이 인스턴스 고유)

> **D26**: 소비 **규약**의 SSOT는 `iac-module-library` `docs/`(D-CONSUME 계열) **하나**다.
> 이 문서는 **그 규약을 이행한 이 인스턴스의 사실**만 기록한다.

> **이 문서는 값이 아니라 포인터를 기록한다.** D25는 계정 식별 정보(버킷명·계정 ID·Role ARN)를
> git에 남기지 않기로 했다 — `backend.tf`가 고객사에 복사해 줄 템플릿이기 때문이다. 그 근거를
> 이 문서에도 적용한다: **"값이 무엇인가"가 아니라 "어디에 있는가"를 적는다.**

> **workload code는 `demo`다.** 과거 `ref`로 부트스트랩된 인스턴스가 있었으나 전량 파기하고
> `demo`로 재구축했다 — 이 문서는 현재 살아 있는 `demo` 자원만 서술한다.

---

## 1. git에 적어도 되는 값

노출돼도 AWS 리소스 식별로 이어지지 않는 것들이다.

| 항목 | 값 | 용도 |
|------|-----|------|
| GitHub org | `skax-ca` | — |
| GitHub org 숫자 ID | `310520211` | OIDC `sub` 조립(D28) |
| 이 repo 숫자 ID | `1316830050` | OIDC `sub` 조립(D28) |
| 모듈 repo | `skax-ca/iac-module-library` | 소싱 대상 |
| workload code | `demo` (D24) | `Name` 태그 2번째 토큰 |
| env | `dev`(spoke 첫 인스턴스) · `hub`(team 계정의 단일 고정 거처) | — |
| region / regioncode | `ap-northeast-2` / `an2` | — |
| OIDC 발급자 | `token.actions.githubusercontent.com` | provider URL(계정마다 URL당 1개 — hub와 spoke는 계정이 달라 각자 가진다) |
| OIDC audience | `sts.amazonaws.com` | `aws-actions/configure-aws-credentials` 기본값 |
| 실행 Role **이름** | `iamr-demo-dev-an2-gha-exec-01`(dev) · `iamr-demo-hub-an2-gha-exec-01`(hub) | ARN은 아래 「2」. **각자 소유**, 공유 아님 |
| 입구 Role **이름** | `iamr-demo-dev-an2-gha-entry-01`(dev) · `iamr-demo-hub-an2-gha-entry-01`(hub) | ARN은 아래 「2」. **각자 소유**, 공유 아님 |
| VPC `Name` 태그 | `vpc-demo-dev-an2-main` · `vpc-demo-hub-an2-main` | ID는 계정 식별로 이어지므로 적지 않는다 |
| networking state key | dev: `dev/networking.tfstate`(dev 버킷) · hub: `hub/networking.tfstate`(hub 버킷) | backend `key`, **버킷도 dev·hub 각자** |
| eks state key | dev: `dev/eks.tfstate`(dev 버킷) · hub: `hub/eks.tfstate`(hub 버킷) | backend `key`, **버킷도 dev·hub 각자** |
| GitHub App slug | `skax-ca-module-reader` | 모듈 소싱 인증(D20) |
| App Client ID | repo 변수 `MODULE_READER_CLIENT_ID` | `create-github-app-token`의 `client-id` |

> 이 repo는 2026-07-15 이후 생성됐으므로 OIDC `sub`가 immutable 형태
> (`repo:<org>@<org_id>/<repo>@<repo_id>:...`)다 — 아래 「3」의 신뢰 정책이 그 형태를 쓴다.

GitHub App 기반 소싱(private repo 모듈을 App 설치 토큰으로 clone)은 검증 완료됐다 —
App은 이 repo 하나에만 `contents: read`+`metadata: read`로 설치되어 있고, 발급 토큰은
1시간 만료다. 검증 실험(음성 대조군 포함)의 상세 기록은 git 이력의 이전 버전을 참조한다.

---

## 2. git에 두지 않는 값 — 어디에 있는가

**이유가 세 종류다. 섞어 쓰면 판단이 흐려진다.**

| 이유 | 의미 |
|------|------|
| 비밀 | 유출 자체가 사고다. GitHub secret에만 둔다 |
| 비노출 | 비밀은 아니지만 굳이 알릴 이유가 없다(계정 식별 → IAM principal 열거 가능). D25 |
| 이식성 | 노출돼도 무해하지만 **고객사가 값만 바꾸면 되게** 하려고 코드 밖에 둔다 |

| 항목 | 이유 | 저장 위치 | 주입 경로 |
|------|------|----------|----------|
| state 버킷명(dev) | 비노출 | repo 변수 `DEV_TF_STATE_BUCKET` / 로컬 gitignore된 `backend.hcl` | `tofu init -backend-config="bucket=..."` |
| AWS 계정 ID(dev) | 비노출 | 입구 Role ARN에 포함 → repo 변수 `DEV_AWS_ENTRY_ROLE_ARN` | `configure-aws-credentials`의 `role-to-assume` |
| 입구 Role ARN(dev) | 비노출 | repo 변수 `DEV_AWS_ENTRY_ROLE_ARN` | 동일 |
| 실행 Role ARN(dev) | 비노출 | repo 변수 `DEV_AWS_EXEC_ROLE_ARN` | provider `assume_role.role_arn`(`TF_VAR_execution_role_arn` 경유) |
| GitHub App private key | 비밀 | repo secret `MODULE_READER_KEY` | `create-github-app-token` |
| GitHub App Client ID | 이식성 | repo 변수 `MODULE_READER_CLIENT_ID` | `create-github-app-token`의 `client-id` |

Client ID는 비밀이 아니다 — public `/apps/{slug}` 엔드포인트로 조회되고 워크플로 로그에도 찍힌다.
변수로 두는 이유는 이식성이다: 고객사는 자기 App을 만들고 변수만 바꾸면 워크플로를 안 고친다.

버킷명 형식은 `s3-demo-dev-an2-tfstate-<guid12>`(D25). GUID는 `bootstrap.sh`가 생성하고
실행자에게 출력한다 — 이 문서에 적지 않는다.

**검증**: 실제 버킷명 문자열로 `git grep`했을 때 0이어야 한다(D25 수용 기준).

`EXPECTED_ACCOUNT`는 기본값 없는 환경변수로 부트스트랩에 요구된다(`EXPECTED_ACCOUNT=<12자리>
bash bootstrap/bootstrap.sh`) — 안전장치가 값을 소비하는 함수(`oidc_arn()`·`role_arn()`)에
쓰이므로 지울 수 없고, 해시 저장은 계정 ID 공간이 10¹²뿐이라 전수 해싱이 가능해 기각됐다(D25).

---

## 3. OIDC `sub` claim — 신뢰 정책에 넣을 형태

`environment`를 선언한 job만 `environment` claim을 받고, **그 claim이 `ref`를 덮어쓴다** — 그래서
apply job(`environment: dev`)의 브랜치 제한을 `sub`로 걸 수 없다(D28, GitHub deployment branch
policy가 대신 그 자리를 맡는다 — 아래 「5」).

```json
"StringEquals": { "token.actions.githubusercontent.com:aud": "sts.amazonaws.com" },
"StringLike": {
  "token.actions.githubusercontent.com:sub": [
    "repo:skax-ca@310520211/iac-reference-infra@1316830050:ref:refs/heads/main",
    "repo:skax-ca@310520211/iac-reference-infra@1316830050:environment:dev"
  ]
}
```

> 값에 와일드카드가 없으므로 `StringEquals`로도 되지만, 향후 환경·브랜치 추가 시 패턴을 쓰게
> 되므로 `StringLike`로 둔다. ⚠️ **`repo:...*` 같은 넓은 와일드카드는 쓰지 않는다** — org 내
> 다른 repo가 이 Role을 assume할 수 있게 된다.

---

## 4. 부트스트랩 자원 — 이름과 값의 소재

`bootstrap/README.md`의 「2. 기대 상태 (SSOT)」 표가 SSOT다. 이 절은 그곳을 가리키고 값의
소재만 적는다.

| 리소스 | 이름 | 값의 소재 |
|--------|------|----------|
| state 버킷(dev) | `s3-demo-dev-an2-tfstate-<guid12>`(버저닝·SSE·퍼블릭차단·lifecycle) | repo 변수 `DEV_TF_STATE_BUCKET` / 로컬 `backend.hcl` |
| OIDC provider | `Name` 태그 `iamoidc-demo-an2-gha`(계정에 하나뿐, 식별자는 URL) | 이름이 곧 값 |
| **입구** Role(dev) | `iamr-demo-dev-an2-gha-entry-01` | ARN은 repo 변수 `DEV_AWS_ENTRY_ROLE_ARN` |
| **실행** Role(dev) | `iamr-demo-dev-an2-gha-exec-01`(D27-1) | ARN은 repo 변수 `DEV_AWS_EXEC_ROLE_ARN` |

`AWSAFTExecution`은 손대지 않는다 — 신뢰 정책이 깨진 채로 남아 있고, 우리 자산이 아니므로
우리 문제가 아니다(D27-1).

버저닝 + `use_lockfile=true`는 lock 객체 버전을 폭증시킨다(OpenTofu 공식 경고) — lifecycle
규칙(비현행 7일·불완전 MPU 7일)이 그래서 선택이 아니다(D29).

---

## 5. 배포 루트 형상과 CI 제약

### 5.1 networking 형상 = enterprise

모듈 repo `examples/vpc-enterprise`(9그룹 착수 템플릿)를 이 계정 대역에 맞춰 배포한다.

| CIDR | 성격 | 배치 |
|------|------|------|
| `10.50.0.0/24` primary | uniq 소형 — 인프라 전용 | `ep-uniq`·`tgw-uniq` |
| `10.51.0.0/16` secondary | uniq — 라우팅 가능 | `pub`·`elb`·`vm`·`node`·`db`·`data` |
| `100.64.0.0/16` secondary | dup 허용(RFC 6598) | `pod-dup` |

서브넷 20개·RT 11개(+ AWS 기본 RT 1개)·NAT 1개(`single_nat_gateway`)·IGW 1개·Flow Logs 1개.
`deletion_protection = true`(D12) — teardown이 2단계다.

### 5.2 계정 자동 태거 — `ignore_tags`가 실제로 필요하다

이 계정은 자동 태거가 붙는다(`CreationTime`·`Creator`·`cz-org`·`cz-owner`·`cz-ext1~3`, 생성
주체와 무관하게 동일) — `providers.tf`가 `keys = ["CreationTime","Creator"]` +
`key_prefixes = ["cz-"]`로 방어한다. **판정 기준은 두 번째 apply가 `No changes`를 내는가**다.

### 5.3 승인 게이트 — GitHub Free 플랜 제약

이 org(`skax-ca`)는 GitHub Free 플랜이라 **required reviewers·wait timer를 걸 수 없다**
(`422 ... billing plan supports ...`). `deployment branch policy`만 걸린다(허용 브랜치 `main`
하나) — `environment`가 `sub`의 `ref`를 덮어써서 IAM으로 표현 불가능했던 브랜치 제한을
이 레이어가 대신 건다(「3」 참조).

채택한 운영 형태: `push`(main)는 plan까지만, `workflow_dispatch`가 apply를 연다. "머지 = 검토
지점"(강제력 없음) + "dispatch를 누르는 행위 = 승인"(CLAUDE.md 「4-1」).

### 5.4 backend는 provider의 `assume_role`을 쓰지 않는다

OpenTofu 공식 문서가 backend 자격증명은 provider 설정과 **독립적으로** 해결된다고 명시한다.
입구 Role의 권한은 `sts:AssumeRole` 하나뿐이라(D27-1 최소권한), backend에도 같은 실행 Role을
**직접** assume 시켜야 한다:

```hcl
# CI가 repo 변수로 조립하는 backend.hcl(gitignore 대상 이름이라 커밋될 수 없다)
bucket       = "…"
key          = "dev/networking.tfstate"   # eks는 dev/eks.tfstate
region       = "ap-northeast-2"
use_lockfile = true
assume_role = {
  role_arn     = "…/iamr-demo-dev-an2-gha-exec-01"
  session_name = "tofu-backend-<run_id>"
}
```

`-backend-config=KEY=VALUE`로는 표현할 수 없다 — 문자열 값만 받는데 `assume_role`은 객체다.
그래서 CI도 HCL 파일을 조립해 넘긴다(로컬 규약과 형태가 같아지는 부수 효과). 기각한 대안은
"입구 Role에 S3 권한을 추가한다"다 — 입구 Role의 권한을 "실행 Role assume 하나뿐"으로 좁힌
D27-1의 신뢰 경계가 깨진다.

개인 IAM user는 실행 Role을 assume할 수 없다(신뢰가 입구 Role뿐) — 로컬 `plan`이 성립하지
않는 이유이자 결함이 아니라 신뢰 경계다(`live/dev/*/README.md`의 관련 절 참조).

### 5.5 repo 변수는 CI 로그에 평문으로 남는다

GitHub은 **secret만 마스킹**한다. repo 변수(`vars.*`)는 마스킹 대상이 아니다 — repo read
권한자는 워크플로 로그(`-backend-config="bucket=..."` 등)에서 값을 볼 수 있다. private repo이고
plan artifact(`retention-days: 1`)와 노출 대상이 같으므로 현재는 수용한다 — 완화하려면 첫
스텝에서 `::add-mask::`를 쓰거나 값을 secret으로 옮긴다(열린 항목, 아래 「9」).

### 5.6 hub/spoke 부트스트랩 소유

`live/hub/{networking,eks}`는 team 계정의 단일 고정 거처다. `live/dev/{networking,eks}`는
spoke의 첫 인스턴스로 asset 계정에 다시 배포한다. 따라서 hub와 dev는 부트스트랩 자원(state
버킷·입구/실행 Role)을 **각자** 갖는다:

| 자원 | dev | hub |
|------|-----|-----|
| state 버킷 | `s3-demo-dev-an2-tfstate-*` | `s3-demo-hub-an2-tfstate-*`(별도) |
| 입구/실행 Role | `iamr-demo-dev-an2-gha-{entry,exec}-01` | `iamr-demo-hub-an2-gha-{entry,exec}-01`(별도) |
| Role 신뢰 sub 패턴 | 2패턴(`ref:refs/heads/main`·`environment:dev`, `pull_request` 없음) | 2패턴(`ref:refs/heads/main`·`environment:hub`, `pull_request` 없음) |

OIDC provider도 계정마다 각자 가진다. AWS가 URL당 계정에 정확히 1개만 허용하므로, 같은 계정 안에서
나눌 수 없다는 제약은 그대로다. `Name` 태그에서 env 토큰을 뺐다(`iamoidc-demo-an2-gha`,
`bootstrap/config.sh` 참조).

⚠️ **`hub/{networking,eks}.tfstate` 위치**: 이 상태 파일들이 dev 버킷에 있으면 아직
`tofu init -migrate-state`로 hub 전용 버킷으로 옮기지 않은 것이다 — 옮긴 뒤에는 hub 버킷에
있어야 정상이다. `live/hub/*/backend.hcl`의 `bucket` 값이 현재 사실이다.

### 5.7 workbench — 클러스터 운영 접근(SSM 경유)

hub 클러스터에 `kubectl`로 접근하는 운영 인스턴스는 `Name = ec2-demo-hub-an2-workbench-01`
이다(private-only, 퍼블릭 IP 없음 — SSM Session Manager/RunShellScript로만 도달).

⚠️ **인스턴스 ID를 어디에도 하드코딩하지 않는다.** workbench는 교체되면 ID가 바뀌므로
ID를 박아 두면 곧 stale해진다 — 안정적 식별자는 결정적 `Name` 태그뿐이다(네이밍 규약이
보장하는 값이라 교체돼도 불변). ID는 그 Name으로 조회한다:

```bash
aws ec2 describe-instances --profile team --region ap-northeast-2 \
  --filters "Name=tag:Name,Values=ec2-demo-hub-an2-workbench-01" \
            "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].InstanceId' --output text
```

⚠️ SSM `AWS-RunShellScript`는 로그인 셸이 아니라 `$HOME`이 없다 — 명령 첫 줄에
`export HOME=/root`와 `export KUBECONFIG=/root/.kube/config`를 넣지 않으면 kubectl이
kubeconfig를 찾지 못한다. `--parameters`는 인라인 배열이 개행을 뭉개므로 JSON 파일
(`file://...`)로 넘긴다.

> dev·spoke도 같은 규칙이며 `Name`의 env 토큰만 다르다: `ec2-demo-<env>-an2-workbench-01`.

---

## 6. apply 판정표

networking 루트의 미검증 6항목(모듈 repo `docs/`의 VPC 모듈 계약)에 대한 현재 판정이다.
**apply 결과를 서술할 때는 이 표에 기록된 것만 쓴다** — networking README가 이 절을
판정 SSOT로 참조한다.

| # | 항목 | 결과 |
|---|------|------|
| 1 | secondary CIDR `depends_on` 순서 | ✅ 3개 CIDR 모두 `associated` |
| 2 | primary/secondary 조합 제약 | ✅ API가 조합을 수락 |
| 3 | CIDR 겹침 없음 | ✅ 파생 서브넷 20개 전부 생성 |
| 4 | Flow Logs 실제 배달 | ✅ 로그 스트림에 실제 레코드 도착 확인 |
| 5 | `prevent_destroy` 실동작(D12) | ✅ `vpc_enabled = false` plan이 D12 validation으로 거부됨(apply 없이 차단) |
| 6 | `git tag` 소싱 경로(CI `init`) | ✅ App 토큰 + `insteadOf`로 소싱 성공 |
| — | 가짜 diff 없음(`ignore_tags`) | ✅ 두 번째 apply가 `No changes` |

5번은 D12의 **교차변수 validation** 가드(`vpc_enabled=false` + `deletion_protection=true` → plan
거부)만 판정됐다 — 실제 `tofu destroy`/replace를 막는 `prevent_destroy` lifecycle 메타 인자는
모듈 계약 테스트가 별도로 증명하고, 라이브 destroy-plan은 실행하지 않았다(deploy 워크플로에
destroy 경로가 없고 사용자가 자산 유지를 택함) — 두 가드를 뭉뚱그리지 않는다.

두 job(plan·apply) 모두 GitHub App 토큰(모듈 소싱)·OIDC(입구 Role)·2단 체인(실행 Role, provider
+ backend 양쪽)이 한 run 안에서 전부 동작하는 것이 검증됐다.

## 7. CI 권한 구조 — plan/apply를 분리하지 않는 이유

plan job과 apply job 모두 **같은 실행 Role**(`iamr-demo-dev-an2-gha-exec-01`,
`AdministratorAccess`)을 assume한다. `tofu plan`도 state lock을 잡으므로 "plan은 read-only"가
완전히 성립하지는 않는다.

**결론(변경 없음, 문서화만)**: 분리하지 않는다.

- plan 전용 읽기 전용 Role을 분리하는 안은 기각 — 2단 체인을 plan용으로 중복 구성하면 CI 설정
  복잡도와 IAM 리소스만 늘고, plan job의 `permissions` 자체는 이미 최소(`id-token: write`·
  `contents: read`)다.
- plan job을 없애고 apply만 두는 안도 기각 — `tofu apply`(재-plan)가 승인한 것과 다른 것을
  적용하게 된다. `tofu apply tfplan`이 이 repo의 약속이다.
- 이 구조는 선택이 아니라 소비 규약(모듈 repo D-CONSUME)이 "plan·apply를 같은 워크플로·같은
  run에 두라"고 요구한 결과다 — 별도 워크플로로 쪼개면 plan artifact를 run 경계 밖에서 찾아야
  하고, 그 조회 지점이 곧 "승인한 계획 ≠ 적용된 계획" 구멍이 된다.
- 수용 근거: job 간 자격증명 이동이 없고(각 job이 독립적으로 OIDC 인증), plan artifact는 같은
  run 안에서만 apply job이 소비하며(`retention-days: 1`), plan이 state를 직접 수정하지도 않는다
  (lock만 잡고 해제).

---

## 8. 모듈 소싱 — shallow clone

모든 모듈 소싱 URL에 `&depth=1`을 붙인다(OpenTofu가 지원하는 shallow clone — `ref`가 태그
이름이어야 동작하고, 커밋 ID만으로는 동작하지 않는다). 전부 태그 기반 핀이므로 조건을 만족한다.

```hcl
source = "git::https://github.com/skax-ca/iac-module-library.git//modules/vpc?ref=<main.tf 참조>&depth=1"
```

정확한 핀은 각 배포 루트의 `main.tf`가 SSOT다 — 여기 버전 번호를 다시 적지 않는다(과거 이
줄이 버전 번호를 나열하다 두 번 낡아 재발했다 — 숫자 나열 자체를 없애는 것이 구조적 해법이다).

---

## 9. Future Work — 열린 항목

| # | 항목 | 참고 |
|---|------|------|
| 1 | plan artifact 암호화 | `retention-days: 1`은 완화책 — 「5.5」 repo 변수 평문 로그와 같은 계열 |
| 2 | repo 변수 평문 로그 완화 | `::add-mask::` 또는 secret 이전 — 「5.5」 |
| 3 | deepinit 실행 | `.tf` 분석 대상이 이제 존재함 — 실행 시점 결정 필요 |
| 4 | 승인 게이트 강제력 부재 | GitHub Team 이상 요금제로 전환 시 `environment: dev`에 required reviewers 적용 가능 — 「5.3」 |

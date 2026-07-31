# live/dev/networking

VPC 하나를 배포하는 루트다. 모듈은 `iac-module-library` 에서 **git tag 로 소싱**한다(D20).

> ⚠️ **이 디렉토리는 코드만 보고는 어느 버킷·어느 계정을 가리키는지 알 수 없다.** 의도된 것이고
> (D25), 그 대가로 이 README 가 **주입 변수명을 명시할 의무**를 진다. 아래 §1 이 그 이행이다.

---

## 1. 주입되는 값 — 코드에 없는 것들

| 무엇 | 어디서 | 어떻게 |
|------|--------|--------|
| state 버킷명 | CI: repo 변수 `TF_STATE_BUCKET` · 로컬: gitignore 된 `backend.hcl` | `tofu init -backend-config=...` |
| state key | 같음 (`dev/networking.tfstate`) | 동일 |
| 리전 / `use_lockfile` | 같음 | 동일 |
| **실행 Role ARN** | CI: repo 변수 `AWS_EXEC_ROLE_ARN` · 로컬: `TF_VAR_execution_role_arn` | provider `assume_role` |
| 입구 Role ARN | CI: repo 변수 `AWS_ENTRY_ROLE_ARN` | `configure-aws-credentials` (워크플로) |

`backend.hcl` 은 **이 디렉토리에** 둔다. `.gitignore` 의 `backend.hcl` 패턴은 앵커가 없어 모든
depth 에서 잡히고, pre-commit 훅 1단계가 staged 여부를 별도로 검사한다.

> ⚠️ **왜 루트가 아니라 여기인가.** `tofu -chdir=live/dev/networking init -backend-config=backend.hcl`
> 에서 `-chdir` 은 cwd 를 바꾸므로 상대 경로가 **이 디렉토리 기준**으로 풀린다. repo 루트에 두면
> `../../../backend.hcl` 을 써야 하고, 그 형태가 고객사 복사본에 그대로 나가면 매번 틀린다.

---

## 2. 로컬에서 할 수 있는 것 / 없는 것

```bash
# ✅ 할 수 있다 — backend·자격증명 없이 모듈 소싱과 문법을 확인한다
tofu -chdir=live/dev/networking init -backend=false
tofu -chdir=live/dev/networking validate

# ✅ 할 수 있다 — 실제 backend 에 붙는다(state 읽기는 개인 IAM user 권한으로 된다)
tofu -chdir=live/dev/networking init -backend-config=backend.hcl
```

```bash
# ⛔ 할 수 없다 — 실행 Role 의 신뢰 정책이 입구 Role 하나만 허용한다(D27-1)
tofu -chdir=live/dev/networking plan
#   → AccessDenied. 개인 IAM user 는 assume 대상이 아니다.
```

**이것은 결함이 아니라 신뢰 경계다.** 로컬 plan 을 가능하게 하려면 실행 Role 의 신뢰를 넓혀야
하는데, D27-1 이 공용 계정(F13)에서 일부러 좁힌 부분이다. `plan` 은 CI 에서만 돈다.

---

## 3. 형상

모듈 repo `examples/vpc-enterprise` 를 착수 템플릿으로 복사해 이 계정 대역에 맞춘 것이다.

### CIDR 3계층

| CIDR | 성격 | 배치 그룹 |
|------|------|-----------|
| `10.50.0.0/24` (primary) | uniq 소형 — 인프라 전용 | `ep-uniq` · `tgw-uniq` |
| `10.51.0.0/16` (secondary) | uniq — 라우팅 가능(온프레미스 도달 가정) | `pub` · `elb` · `vm` · `node` · `db` · `data` |
| `100.64.0.0/16` (secondary) | dup 허용 — 비라우팅(RFC 6598) | `pod-dup` |

> 세 대역 모두 **대상 계정에서 사용 중이 아님을 실측**하고 골랐다(2026-07-31, VPC 23개의 연결
> CIDR 전수 조회). 근거는 `main.tf` 의 locals 주석에 있다.

### 서브넷 그룹 (`az_count = 3`, `az_selection = ["a", "c", "b"]`)

| 그룹 키 | type | AZ | 크기 | eks_role |
|---------|------|----|------|----------|
| `pub-uniq` | public | 2 (a·c) | /24×2 | `elb` |
| `elb-uniq` | isolated | 2 (a·c) | /24×2 | `internal-elb` |
| `vm-uniq` | private | 2 (a·c) | /20×2 | — |
| `node-uniq` | private | 2 (a·c) | /24×2 | — |
| `pod-dup` | isolated | 2 (a·c) | /18×2 | — |
| `db-uniq` | isolated | 2 (a·c) | /26×2 | — |
| `data-uniq` | isolated | **3 (a·c·b)** | /24×3 | — |
| `ep-uniq` | isolated | 2 (a·c) | /27×2 | — |
| `tgw-uniq` | isolated | **3 (a·c·b)** | /28×3 | — |

- 서브넷 **20개** · RT 11개 · NAT 1개 · IGW 1개 · Flow Logs 로그 그룹 1개.
- 2AZ 그룹이 모두 a·c 에 몰리는 것은 **의도된 결과**다 — b존은 3AZ 그룹(`data`·`tgw`) 전용이다.

### 이 루트가 만들지 **않는** 것

TGW·attachment · 온프레미스 대역 라우트 · prefix list · KMS 키. 전부 foundation(공유 리소스)
소관이거나 운영 라우트다. `outputs.tf` 의 `route_table_ids_by_group` 이 나중에 얹을 앵커다(D3).

---

## 4. 이 루트가 판정하는 것 / 판정하지 못하는 것

⚠️ **판정표는 `docs/deployment-facts.md` §5 가 SSOT 다.** 여기 요약을 복제하지 않는다 —
두 곳에 적으면 곧 갈라진다. `apply` 결과를 서술할 때는 그 표에 기록된 것만 쓴다(CLAUDE.md §7).

---

## 5. teardown

`deletion_protection = true` 이므로 **2단계**다. 결함이 아니라 보호의 정의다.

```
① deletion_protection = false 로 apply   # prevent_destroy 해제
② vpc_enabled = false 로 apply            # 전 리소스 파기
```

⚠️ ①을 건너뛰고 ②를 하면 모듈의 변수 validation 이 먼저 막는다(엔진의 `prevent_destroy` 메시지
보다 친절하다). 공용 계정이므로 **파기 plan 의 목록도 사람이 읽는다**(D27-2).

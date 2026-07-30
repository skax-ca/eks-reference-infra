# iac-reference-infra

**레퍼런스 소비 repo** — `iac-module-library`의 모듈을 **git tag로 소싱**하는 배포 루트.

실 고객사 배포가 아니다. **소비 경로를 끝까지 통과시키는 리허설**이고, 통과한 형태를 고객사
repo로 복사해 주는 것이 이 repo의 존재 이유다.

## 왜 이 repo가 고객사 repo보다 먼저인가

`vpc-v1.0.0`의 증거는 전부 `plan` 수준이었다. 소비 경로에는 한 번도 통과하지 않은 구간이 셋 있고,
셋 다 **첫 `apply`에서 터진다**:

1. private repo의 `git tag` 소싱 인증
2. state 버킷·OIDC Role의 부트스트랩 순서(닭-달걀)
3. OIDC `sub` claim 형태

고객 앞에서 처음 부딪히는 것과, 리허설에서 잡아 템플릿으로 복사해 주는 것은 완전히 다른 일이다.

## 설계 문서는 어디에 있나

⛔ **설계는 이 repo에 없다.** 소비 경로 규약의 SSOT는 모듈 repo에 있다:

| 문서 | 내용 |
|------|------|
| `iac-module-library` `docs/design/50-reference-consumer-repo.md` | **D-CONSUME** — D20~D29 결정과 근거. 이 repo의 모든 구조가 여기서 나온다 |
| 같은 repo `docs/consumer/*` | 🗄️ **TFC 시절 잔재 — 규약이 아니다**(D26-1). 인용 금지. 개정하지 않는다 |
| 이 repo `docs/deployment-facts.md` | 이 **인스턴스**의 배포 사실 — 값이 아니라 **어디에 있는지**를 기록한다 |

이 분리는 D26이다: **규약은 모듈 repo(모든 소비 repo가 따르는 계약), 사실은 소비 repo(인스턴스 값).**

## 구조

```
bootstrap/            # state 버킷 · OIDC provider · Role  — IaC 밖(D21)
├── bootstrap.sh      #   멱등. 재실행이 안전해야 한다
├── verify.sh         #   read-only drift 검사 (plan 의 대체물)
└── README.md         #   기대 상태 표 + IaC 승격용 import 초안
live/dev/networking/  # VPC 하나 (D22 — 목표 토폴로지 유지)
.github/workflows/    # deploy.yml — plan → 승인 → apply 를 한 run 안에서
```

## 로컬에서 쓰기

```bash
git config core.hooksPath .githooks     # clone마다 1회

# backend 는 부분 설정이다(D25) — 버킷명은 git에 없다.
cat > live/dev/networking/backend.hcl <<'EOF'
bucket       = "<bootstrap.sh 가 출력한 버킷명>"
key          = "dev/networking.tfstate"
region       = "ap-northeast-2"
use_lockfile = true
EOF

tofu -chdir=live/dev/networking init -backend-config=backend.hcl
tofu -chdir=live/dev/networking plan
```

⛔ `backend.hcl`은 `.gitignore`에 있고 pre-commit 훅이 staged 여부를 따로 검사한다.
**커밋하지 말 것** — 버킷명이 git에 들어가면 D25의 근거가 그 자리에서 무너진다.

## 검증 게이트

```
tofu fmt -recursive -check → tflint --recursive → trivy config . → tofu validate
bootstrap/verify.sh        # 부트스트랩 drift (D21 완화책)
```

`tofu test`는 없다 — 배포 루트는 모듈이 아니다. 모듈 계약 검증은 `iac-module-library`의
`modules/vpc/tests/plan.tftest.hcl`이 담당한다.

## 현재 상태

**Phase 4 (VPC 배포) 대기 중.** `live/`와 워크플로가 아직 비어 있다.

| Phase | 내용 | 상태 |
|-------|------|------|
| 1 | repo 골격 + GitHub App | ✅ 완료 (`cfb575a` · D20 실측 검증 `efe1776`) |
| 2 | OIDC `sub` claim 실측 | ✅ 완료 (`0cc0ec0`+`a2416d9` · 값은 `docs/deployment-facts.md` §3) |
| 3 | `bootstrap.sh` (버킷·OIDC·Role) | ✅ 완료 — 멱등·음성 테스트·D25 검증 통과 (`bootstrap/README.md` §4) |
| 4 | `live/dev/networking` + apply | ⏭️ **다음** |
| 5 | 실측 반영 → 모듈 repo `design/50` 개정 + 이 repo `docs/` 갱신 | ⏸ 대기 |

> ⚠️ Phase 5는 **`docs/consumer/*` 개정이 아니다**(D26-1로 변경). 그 디렉토리는 TFC 잔재 보관소이고,
> 개정 대상은 규약의 SSOT인 모듈 repo `docs/design/50-reference-consumer-repo.md`다.

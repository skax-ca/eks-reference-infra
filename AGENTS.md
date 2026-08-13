# AGENTS.md — 에이전트 작업 지침

**읽는 사람**: 이 repo에서 작업하는 AI 에이전트.

이 repo에서 작업하기 전에 **`CLAUDE.md`를 먼저 읽는다.** 이 파일은 그 규칙을 전제로
"어디를 고치면 무엇이 깨지는가"를 다룬다.

## 이 repo가 무엇이 아닌가

- ⛔ **모듈 repo가 아니다.** `modules/`가 없고 `tofu test`도 없다. 여기에 모듈을 만들지 않는다 —
  모듈은 `iac-module-library`에 만들고 태그로 소싱한다.
- ⛔ **설계 문서 소유자가 아니다.** 규약을 바꿔야 하면 모듈 repo의 `docs/`를 고치고 여기로
  내려온다. 역방향은 drift다.
- ⛔ **실 고객사 배포가 아니다.** 리허설이고, 통과한 형태를 복사해 준다.

## 디렉토리별 소유 관심사

| 경로 | 무엇 | 고칠 때 주의 |
|------|------|-------------|
| `.githooks/` | pre-commit/pre-push 훅 | 실행 비트(100755) 필수. chmod 누락 시 조용히 안 돈다 |
| `bootstrap/` | state 버킷·OIDC·Role. **IaC 밖**(D21) | 멱등성이 요건이다. `verify.sh`도 같이 고친다 — 기대 상태가 갈라지면 완화책이 무력해진다 |
| `live/dev/networking/` | VPC 배포 루트 (apply 완료) | `backend.tf`는 **비어 있어야 한다**(D25). 버킷명을 여기 넣지 않는다 |
| `live/dev/eks/` | EKS 배포 루트 (apply 완료) | `backend.tf`는 networking과 같은 부분 설정 패턴이다 |
| `.github/workflows/` | plan → 승인 → apply (네트워킹·eks 각 워크플로) | **한 run 두 job**을 유지한다. 쪼개면 "승인한 계획 ≠ 적용된 계획" 구멍이 열린다 |
| `docs/deployment-facts.md` | 이 인스턴스의 사실 | **값이 아니라 포인터**를 적는다. 계정 ID·버킷명·Role ARN을 여기 쓰지 않는다 |

## 이것을 하면 설계가 깨진다

| 하면 안 되는 것 | 왜 |
|----------------|-----|
| `backend.tf`에 `bucket = "..."` 추가 | D25 근거(계정 식별 정보 비노출 + 템플릿 재사용성)가 무너진다. `-backend-config`로 주입한다 |
| `backend.hcl` 커밋 | 같은 이유. `.gitignore` + pre-commit 훅이 이중으로 막는데 `--no-verify`로 뚫지 말 것 |
| `source`를 `git::ssh://`로 변경 | 로컬/CI 갈래가 생긴다. 인증은 `insteadOf`가 CI에서만 주입한다(D20) |
| `source`의 `?ref=`를 브랜치로 변경 | 정확 태그 핀이 승격 게이트다. 브랜치는 게이트를 없앤다 |
| plan job에 `environment:` 추가 | `sub`가 바뀌어 신뢰 정책과 불일치한다(D28). apply job만 선언한다 |
| apply를 `tofu apply`(재-plan)로 변경 | 승인한 계획과 다른 것을 적용한다. `tofu apply tfplan`이어야 한다 |
| 약어를 임의 생성 | 카탈로그가 SSOT다. 없으면 **물어서 모듈 repo에 등재 후** 사용 |
| 개별 리소스에 거버넌스 태그 반복 | 루트 `default_tags`가 100% 담당한다 |
| `.trivyignore`에 모듈 내부 지적 추가 | 어느 repo가 위험을 수락했는지 판정 불가능해진다. 모듈 쪽에서 판단한다 |
| eks 워크플로를 networking과 분리 | artifact 조회가 run 경계 밖으로 가면서 "승인한 계획 ≠ 적용된 계획" 구멍이 열린다 |
| eks plan artifact를 이전 run에서 가져오기 | 같은 이유. plan job도 자기 artifact를 생성해서 apply해야 한다 |
| eks apply를 두 워크플로로 쪼개기 | 한 run 안의 `needs:` 관계가 구조적 보장이 된다 |

## 검증 순서 (건너뛰지 않는다)

```
tofu fmt -recursive -check
tofu -chdir=live/dev/networking init -backend=false   # 모듈 소싱 확인
tofu -chdir=live/dev/networking validate
tofu -chdir=live/dev/eks init -backend=false           # EKS 모듈 소싱 확인 (eks 루트 수정 시)
tofu -chdir=live/dev/eks validate
tflint --recursive
trivy config --skip-dirs '**/.terraform' --tf-exclude-downloaded-modules .
bootstrap/verify.sh                                    # 부트스트랩 drift
```

- git hook이 강제한다: `git config core.hooksPath .githooks` (clone마다 1회)
- **스키마를 추정하지 않는다** — `mcp__opentofu__get-resource-docs`로 확인한다
- ⚠️ `apply` 결과를 서술할 때는 **실제로 판정된 것만** 쓴다(`CLAUDE.md` 참조)

## 하위 AGENTS.md 참조 (hierarchical navigation)

| 하위 디렉토리 | AGENTS.md |
|-------------|-----------|
| `.githooks/` | `pre-commit` / `pre-push` 훅 + 활성화 방법 |
| `.github/workflows/` | 두 배포 워크플로 아키텍처 (deploy-network · deploy-eks) |
| `bootstrap/` | S3 버킷 · OIDC · 2단 Role 생성 스크립트 + verify.sh 계약 |
| `docs/` | deployment-facts.md만 (값x 포인터o 원칙) |
| `live/dev/` | Phase별 배포 루트 (networking + eks 독립 배포) |
| `live/dev/networking/` | VPC 배포 루트 (66개 리소스 apply 완료) |
| `live/dev/eks/` | EKS 배포 루트 (plan only — 71개 리소스 plan 완료) |

## 세션 인계

`.omc/notepad.md`가 유일한 세션 인계 SSOT다(gitignore 예외로 커밋된다).
Phase 완료 시 리드가 갱신하고 커밋한다 — 팀원 에이전트는 `.omc/`를 갱신하지 않는다.

<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-08-04 | Updated: 2026-08-04 -->

# .github/workflows

## 목적
두 개의 배포 파이프라인. 각각 배포 루트 하나씩. **루트마다 워크플로 하나** (D-CONSUME 설계).

## 주요 파일

| 파일 | 목적 |
|------|------|
| `deploy-network.yml` | `live/dev/networking` — push → plan / dispatch → apply |
| `deploy-eks.yml` | `live/dev/eks` — push → plan / dispatch → apply |

## 워크플로 구조

두 워크플로 모두 **같은 패턴**을 따른다:

```
main에 push  →  plan job만 실행 (apply 없음)
workflow_dispatch  →  plan job  →  apply job
```

### 왜 이 패턴인가 (D30-1, 2026-08-03)

- GitHub Free는 environment에 `required reviewers`를 걸 수 없다
- 그래서 **"workflow_dispatch 누름 = 승인"** 이 이 org의 승인 방식
- `pull_request` 트리거 제거 — merge 시 같은 plan을 중복 실행했기 때문

### 동시성 · 격리

| 루트 | concurrency group | state key |
|------|-------------------|-----------|
| networking | `live-dev-networking` | `dev/networking.tfstate` |
| eks | `live-dev-eks` | `dev/eks.tfstate` |

각 루트는 독립적이다 — 하나를 바꿔도 다른 루트를 트리거하거나 취소하지 않는다.

## AI 에이전트 가이드

### 새 워크플로 추가
1. `deploy-network.yml`을 템플릿으로 사용
2. `needs:`로 plan → apply를 **같은 run** 안에서 연결 (cross-run artifact 가져오기禁止)
3. `environment: dev`는 apply job에만 추가 (plan job에는 금지 — D28)
4. 루트별로 concurrency group 설정, `cancel-in-progress: false`
5. plan artifact에 `retention-days: 1` 설정 (리소스 속성이 평문으로 남음)
6. backend `assume_role`은 반드시 `backend.hcl` 파일에 ( `-backend-config=K=V`는 문자열만 받아서不可)

### 반드시 지킬 것

| 하지 말 것 | 이유 |
|-----------|------|
| plan job에 `environment:` 추가 | `sub`이 바뀌어 입구 Role 신뢰 정책과 불일치 |
| `tofu apply`(재-plan) 사용 | 승인한 plan과 다른 것을 적용하게 된다 |
| 이전 run의 artifact 가져오기 | "승인한 계획 ≠ 적용된 계획" 구멍이 열린다 |
| 워크플로 분리 | artifact 조회가 run 경계 밖으로 나가면서 같은 구멍이 생긴다 |

### 토큰 스코핑

두 job 모두 같은 GitHub 토큰을 받지만 **OIDC `sub` 클레임이 다르다**:
- plan: `repo:...:ref:refs/heads/main`
- apply: `repo:...:environment:dev`

입구 Role 신뢰 정책은 2패턴(`ref:refs/heads/main` + `environment:dev`)을 쓰고,
execution Role을 assume하는 것은 `environment:dev` job뿐이다.

<!-- MANUAL: 2026-08-04 — PR#12 merge 후 rename: deploy.yml → deploy-network.yml -->

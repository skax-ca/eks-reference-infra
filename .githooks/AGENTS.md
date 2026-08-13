<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-08-04 | Updated: 2026-08-04 -->

# .githooks

**읽는 사람**: 이 repo에서 작업하는 AI 에이전트.

## 목적
Git pre-commit / pre-push 훅. 로컬 IaC 품질 게이트를 강제한다. `.githooks/`가 표준 훅 디렉토리다(`.git/hooks/` 아님).

## 주요 파일

| 파일 | 설명 |
|------|------|
| `pre-commit` | `fmt → tflint → trivy` + **backend.hcl 유출 검사**. Terraform 파일 staged 시만 실행 |
| `pre-push` | `live/` 변경을 push할 때 `init -backend=false → validate`. backend.hcl 미존재 확인 |

## AI 에이전트 가이드

### 훅 활성화 (클론 후 필수)
```bash
git config core.hooksPath .githooks
```

### 각 게이트 검사 내용

| 단계 | 도구 | 실패 조건 |
|------|------|----------|
| 1 | `grep backend.hcl` | `backend.hcl` staged → exit 1 (버킷명 비노출 강제) |
| 2 | `tofu fmt -recursive -check` | Non-zero exit → 서식 위반 |
| 3 | `tflint --recursive` | Non-zero exit → 린트 위반 |
| 4 | `trivy config` | 모듈 외 코드에서 MEDIUM+ 발견 |

### 우회
`git commit --no-verify`로 모든 훅 우회 가능. **반드시 커밋 메시지에 사유를 남길 것.**
`--no-verify` on `git push`는 불가능 (pre-push hook은 이런 방식으로 우회 불가).

### pre-push 동작
- `live/` 파일이 push될 때만 실행
- `tofu -chdir=<path>` 사용 (`cd` 불필요, 동시 push 안전)
- backend init 생략 (CI 클론에는 `.terraform/` 없음)

<!-- MANUAL: 2026-08-04 — 훅 실행 비트(100755) 확인을 pre-push에서도 했었다 — chmod 누락 시 훅이 조용히 안 돈다는 것을 실측으로 잡았다 -->
<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-08-04 | Updated: 2026-08-04 -->

# docs

## 목적
이 인스턴스의 배포 사실과 증거. **실측으로 증명된 사실**만 이곳에 — 설계나 의견은 아니다.

## 주요 파일

| 파일 | 설명 |
|------|------|
| `deployment-facts.md` | 이 배포 루트의 모든 실측 사실에 대한 **SSOT** |

## AI 에이전트 가이드

### 어디에 무엇을 쓰는가

| 내용 | 위치 |
|------|------|
| 이 repo run의 실측 값 | `deployment-facts.md` |
| 설계 결정과 근거 | `iac-module-library/docs/design/50-reference-consumer-repo.md` (SSOT) |
| 고객사 배포용 문서 | 고객사 repo (이 repo는 템플릿임) |

### deployment-facts.md 구조

일반적인 섹션:
- §1 인증 (GitHub App으로 git tag 소싱)
- §2 계정 정보 (값이 아니라 포인터 — 실제 값은 repo 변수에)
- §3 OIDC `sub` 패턴 (실측)
- §4 부트스트랩 생성 상세
- §5 Phase 4 발견 사항 (backend assume_role, 자동 태거, 승인 게이트, repo 변수)
- §6 판정표 (검증된 것, 미검증인 것)
- §7 plan/apply 권한 분리 결정
- §8 Shallow clone `depth=1`

### 핵심 원칙
**값은 repo 변수에, 포인터는 여기에.**
계정 ID, Role ARN, 버킷 명 — 이 세 가지는 git 추적 파일에 나타나지 않는다.
`docs/deployment-facts.md`는 값이 **어디에 있는지**를 기록하지, 값 자체를 기록하지 않는다.

### 흔한 실수
"발견 내용을 문서화하는 순간"이 부주의한 인증 정보 유출의 가장 위험한 순간이다.
버킷 명 발견을 문서화하는 과정에서 Phase 4에 D25 위반이 발생했다.
**문서에 넣을 내용은 CI 로그에서 가져오지 않는다.**

<!-- MANUAL: -->
<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-08-04 | Updated: 2026-08-04 -->

# docs

**읽는 사람**: 이 repo에서 작업하는 AI 에이전트.

## 목적
두 종류를 담는다. ① 이 인스턴스의 배포 사실과 증거 — **실측으로 증명된 사실**만(설계나
의견은 아니다). ② hub-spoke 패턴의 세우기·걷어내기·운영 절차 — 2026-08-24
`iac-module-library`에서 이관됐다(그 repo의 자체 재구성 계획 Decision E — "패턴별
배포·운영 절차는 이 repo가 아니라 그 패턴의 레퍼런스 배포 repo가 소유한다").

## 주요 파일

| 파일 | 설명 |
|------|------|
| `deployment-facts.md` | 이 배포 루트의 모든 실측 사실에 대한 **SSOT** |
| `hub-lifecycle.md` | hub 세우기·걷어내기(2026-08-24 이관, 이 repo가 SSOT) |
| `spoke-lifecycle.md` | spoke 세우기·걷어내기(2026-08-24 이관, 이 repo가 SSOT) |
| `runbooks.md` | day-2 운영 절차(2026-08-24 이관, 이 repo가 SSOT) |

## AI 에이전트 가이드

### 어디에 무엇을 쓰는가

| 내용 | 위치 |
|------|------|
| 이 repo run의 실측 값 | `deployment-facts.md` |
| hub-spoke 패턴의 세우기·걷어내기·운영 절차 | `hub-lifecycle.md`·`spoke-lifecycle.md`·`runbooks.md`(이 repo가 SSOT) |
| 소비 **규약**(네이밍·backend·OIDC 체인 등)의 설계 결정과 근거 | `iac-module-library`의 `docs/`(SSOT, 변경 없음) |
| 고객사 배포용 문서 | 고객사 repo(이 repo는 템플릿임) |

### 핵심 원칙
**값은 repo 변수에, 포인터는 여기에.**
계정 ID, Role ARN, 버킷 명 — 이 세 가지는 git 추적 파일에 나타나지 않는다.
`docs/deployment-facts.md`는 값이 **어디에 있는지**를 기록하지, 값 자체를 기록하지 않는다.

### 흔한 실수
"발견 내용을 문서화하는 순간"이 부주의한 인증 정보 유출의 가장 위험한 순간이다 —
버킷 명 발견을 문서화하는 과정에서 값이 그대로 git에 새어 들어간 전례가 있다.
**문서에 넣을 내용은 CI 로그에서 가져오지 않는다.**

<!-- MANUAL: -->
# CLAUDE.md

AWS hub-spoke EKS 배포 루트. `iac-module-library`의 모듈을 소비해 세우고 걷어낸다.
규칙(엔진·실행 모델·브랜치·네이밍·주석·문서·모듈 계약 확인)은 `iac-module-library/CLAUDE.md`의
「배포 루트 공통」이 갖는다. 이 파일은 이 repo의 값과 문서 좌표만 갖는다.

## 이 repo가 소유하는 문서 (작업 전에 먼저 읽는다)

- `docs/hub-lifecycle.md`: hub 구축·철거
- `docs/spoke-lifecycle.md`: spoke 구축·철거
- `docs/runbooks.md`: 이미 선 환경 운영

이 repo 고유의 판단(TGW 별도 root, `for_each` key 고정 등)은 해당 `.tf`/`.sh` 인라인 주석이 SSOT다.

## 값

| 항목 | 값 |
|------|-----|
| 배포 루트 | `live/hub/{networking,tgw,eks}` · `live/dev/{networking,eks}`, 5개 전부 **별도 state** |
| state key | `<env>/<component>.tfstate` |
| git 밖 값 | repo 변수 `HUB_*`/`DEV_*`(`TF_STATE_BUCKET`·`AWS_ENTRY_ROLE_ARN`·`AWS_EXEC_ROLE_ARN`) + 로컬 `backend.hcl` |
| 네이밍 | `workload=demo`(hub·dev 동일 필수) · `env=hub|dev` · `region=an2` |
| 루트 간 결합 | `terraform_remote_state` 금지, Name·태그 기반 `data` 조회만 |
| 로컬 게이트 | `git config core.hooksPath .githooks` (clone마다 1회) |

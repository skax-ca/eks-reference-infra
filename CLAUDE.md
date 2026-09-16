# CLAUDE.md

AWS hub-spoke EKS 배포 루트. `iac-module-library`의 모듈을 소비해 세우고 걷어낸다.
규칙(엔진·실행 모델·브랜치·네이밍·주석·문서·모듈 계약 확인)은 `iac-module-library/CLAUDE.md`의
「배포 루트 공통」이 갖는다. 이 파일은 이 repo의 값과 문서 위치만 갖는다.

## 이 repo가 소유하는 문서 (작업 전에 먼저 읽는다)

- `docs/hub-lifecycle.md`: hub 구축·철거
- `docs/spoke-lifecycle.md`: spoke 구축·철거
- `docs/runbooks.md`: 이미 선 환경 운영

패턴 갈림길은 `iac-module-library/docs/architectures/gitops-hub-spoke/aws/`가 갖는다. 이 repo 고유의
판단(TGW 별도 root, `for_each` key 고정 등)은 해당 `.tf`/`.sh` 인라인 주석이 SSOT다.

## 값

| 항목 | 값 |
|------|-----|
| 배포 루트 | `live/hub/{networking,tgw,eks}` · `live/dev/{networking,eks}`, 5개 전부 **별도 state** |
| state key | `<env>/<component>.tfstate` |
| backend | S3 + `use_lockfile = true` |
| git 밖 값 | repo 변수 `HUB_*`/`DEV_*`(`TF_STATE_BUCKET`·`AWS_ENTRY_ROLE_ARN`·`AWS_EXEC_ROLE_ARN`) + 로컬 `backend.hcl` |
| CI 신원 | GitHub OIDC → 입구 Role → 실행 Role(`AdministratorAccess`), 2단 체인 |
| 로컬 apply 가드 | 실행 Role이 입구 Role만 신뢰한다. 개인 IAM user는 관리자여도 `AccessDenied` |
| 네이밍 | `workload=demo`(hub·dev 동일 필수) · `env=hub|dev` · `region=an2` |
| 로컬 게이트 | `git config core.hooksPath .githooks` + `tflint --init` + `brew install shellcheck`(clone마다 1회). aws ruleset 핀 `0.48.0`. 셸 게이트 상세는 `scripts/README.md` |

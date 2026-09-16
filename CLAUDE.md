# CLAUDE.md: 프로젝트 규칙

**읽는 사람**: 이 저장소에서 배포·운영 작업을 하거나 코드를 검토하는 사람(과 Claude Code).

hub-spoke EKS GitOps 패턴의 **레퍼런스 배포 루트**다. `iac-module-library`의 모듈을 **소비**해
실제로 세우고 걷어내는 코드와, 그 절차의 운영 문서를 갖는다. 모듈 자체를 만들지 않는다.

전역 규칙(엔진·설계 검토·브랜치·PR·버전·문체)은 `iac-module-library/CLAUDE.md`와 그 `docs/`가
갖는다. 이 파일은 그 위에 **이 배포 루트에서만 성립하는 것**을 얹는다.

## SSOT 지도

| 무엇 | 어디 |
|------|------|
| 이 repo 고유의 판단(TGW를 별도 root로 분리한 이유, `for_each` key를 계정 ID로 고정한 이유 등) | 그 판단이 적용된 `.tf`/`.sh` 파일의 **인라인 주석**. 별도 설계 문서를 두지 않는다 |
| hub-spoke 패턴의 설계 갈림길과 기각("왜 TGW인가", "왜 self-managed ArgoCD인가") | `iac-module-library` `docs/architectures/gitops-hub-spoke/aws/` |
| 모듈 계약 · 네이밍 약어 · 주석 규칙 · 문서 문체 | `iac-module-library` `docs/module-catalog.md` · `docs/naming/abbreviations/aws.md` · `docs/conventions.md` 「주석」 · `docs/writing-style.md` |
| ArgoCD Application·AppProject·cluster-secret(계층 2) | `eks-platform-gitops` |

**운영 절차 SSOT는 이 repo다.** hub/spoke를 세우고 걷어내는 순서, 자주 막히는 지점, 운영
런북은 아래 세 문서가 소유한다. 작업을 시작하기 전에 해당 절차 문서부터 읽는다:

- [`docs/hub-lifecycle.md`](docs/hub-lifecycle.md): hub 구축·철거
- [`docs/spoke-lifecycle.md`](docs/spoke-lifecycle.md): spoke 구축·철거
- [`docs/runbooks.md`](docs/runbooks.md): 이미 선 환경 운영(접근·업그레이드·GitOps 상태 확인 등)

절차·결정·gotcha(예: Terraform `for_each`에 unknown 값이 섞이면 안 되는 이유, GitHub App private
key 취급 절차)는 위 세 문서나 이 파일에 반영한다. 버전관리되지 않는 로컬 메모에만 적어두고
끝내지 않는다.

## 저장소 구조

```
bootstrap/            state 버킷 · OIDC provider · Role (IaC 밖, 사람이 스크립트로 실행)
live/hub/networking/   VPC (hub)
live/hub/tgw/          Transit Gateway (hub, networking과 분리된 state)
live/hub/eks/          EKS + workbench (hub)
live/dev/networking/   VPC + TGW attachment (spoke 첫 인스턴스)
live/dev/eks/          EKS + workbench + cross-account-trust-role (spoke)
.github/workflows/     배포 루트마다 워크플로 하나(plan은 push, apply/destroy는 workflow_dispatch)
docs/                  운영 절차 SSOT + 이 repo 고유 참조 문서
scripts/               teardown-verify.sh · argocd-seed.sh · validate-*.py
```

같은 repo 안에서 `live/hub/*`와 `live/dev/*`는 **각자 별도 state**를 쓴다(같은 배포 루트
안의 다른 env). `live/hub/networking`과 `live/hub/tgw`·`live/hub/eks`도 서로 분리된 state다.
루트 간 결합은 `terraform_remote_state`가 아니라 **Name·태그 기반 `data` 조회**로만 한다.

## 실행 모델

| 항목 | 규칙 |
|------|------|
| backend | S3 + `use_lockfile = true`. 버킷명은 git에 없다(GitHub 저장소 변수 `HUB_TF_STATE_BUCKET`/`DEV_TF_STATE_BUCKET` + 로컬 `backend.hcl`, 둘 다 git 밖) |
| state key | `<env>/<component>.tfstate` (예: `hub/tgw.tfstate`, `dev/networking.tfstate`) |
| 자격증명 | GitHub OIDC → 입구 Role(`*_AWS_ENTRY_ROLE_ARN`) → 실행 Role(`*_AWS_EXEC_ROLE_ARN`), 2단 체인 |
| plan → apply | plan을 workflow run 안에 저장해 사람이 요약을 읽고 **dispatch를 누르는 것 자체가 승인**이다(`pull_request` 트리거는 의도적으로 두지 않는다) |
| 로컬에서 되는 것 | `init` + `validate`까지. **apply·destroy는 로컬에서 안 된다**(실행 Role이 입구 Role만 신뢰해 개인 IAM user는 관리자여도 `AccessDenied`) |

⚠️ **재시도할 때 `workflow run`을 새로 누르지 않는다.** 실패한 job이 apply라면 `gh run rerun
<run-id> --failed`로 **저장된 plan을 그대로** 재적용한다. 새 dispatch는 plan을 처음부터 다시
돌려 승인한 것과 다른 계획을 만든다.

## 네이밍·태깅

약어와 `Name` 포맷은 module repo의 `docs/naming/abbreviations/aws.md`가 SSOT다(임의 생성 금지).
이 repo에서 실제로 쓰는 값:

- `workload` = `demo`(고정, `live/hub`·`live/dev` 모두 반드시 동일해야 한다)
- `env` = `hub` 또는 `dev`(spoke 첫 인스턴스), `region` = `ap-northeast-2`(`an2`)
- 예: `eks-demo-hub-an2-main-01`, `eks-demo-dev-an2-main-01`

`Name`은 모듈이 `naming` 객체를 받아 합성한다. 배포 루트(이 repo)가 약어를 직접 조합하지 않는다.

## 로컬 게이트 (git hook)

```
pre-commit: 문서 변경 시 scripts/validate-doc-conventions.py → 코드 변경 시 scripts/validate-comment-conventions.py → tofu fmt -check → tflint → trivy config
pre-push:   live/**/*.tf 변경 시 각 루트 tofu validate (모듈 계약 테스트는 module repo가 담당, 여기 없음)
```

clone마다 1회 활성화: `git config core.hooksPath .githooks`. 우회(`--no-verify`)는 긴급 시에만,
사유를 커밋 메시지에 남긴다.

두 검증 스크립트는 module repo의 규칙을 이 repo 안에서 pre-commit으로 즉시 돌리기 위해
**이식**한 것이다(규칙 텍스트의 SSOT는 여전히 module repo). 기계로 잡는 것:

- 주석: 날짜·계획 파일 경로·문서 절 번호·PR 번호 같은 좌표, em-dash. 주석은 "왜 이 값인가"와
  "바꾸면 무엇이 깨지는가"에만 답한다
- 문서(`docs/*.md`·`README.md`·`AGENTS.md`·이 파일): 문서 간 절 번호 인용, 7종 외 이모지
  (`✅⏳❌⚠️⛔🔴🔑`), 400줄 초과, em-dash

## 새 리소스·모듈 인자를 쓰기 전에

이 repo는 모듈 내부를 고치지 않지만, 루트 `main.tf`가 모듈에 넘기는 변수·참조하는 출력은
추정하지 않는다: `mcp__opentofu__get-module-details`(`namespace`·`name`·`target`)로 실제
계약을 확인하거나, `live/*/.terraform/modules/`의 다운로드된 실물 소스를 연다.

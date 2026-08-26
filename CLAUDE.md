# CLAUDE.md: 프로젝트 규칙

**읽는 사람**: 이 저장소에서 배포·운영 작업을 하거나 코드를 검토하는 사람(과 Claude Code).

hub-spoke EKS GitOps 패턴의 **레퍼런스 배포 루트**다. `iac-module-library`의 모듈을 **소비**해
실제로 세우고 걷어내는 코드와, 그 절차의 운영 문서를 갖는다. 모듈 자체를 만들지 않는다.

## 0. 이 repo의 위치 (반드시 먼저 읽을 것)

| repo | 역할 | SSOT |
|------|------|------|
| **이 repo (`eks-reference-infra`)** | hub-spoke 패턴을 **소비해 배포**하는 루트 | 이 배포 코드, GitOps **운영 절차**(구축·철거·런북) |
| `iac-module-library` | Terraform 모듈·설계 | 모듈 계약(`docs/module-catalog.md`), 네이밍 약어(`docs/naming/abbreviations/aws.md`), 아키텍처 결정(`docs/decisions.md`), 문서 문체 규칙(`docs/conventions.md`) |
| `eks-platform-gitops` | ArgoCD Application·AppProject·cluster-secret (계층 2) | GitOps 매니페스트 |

⚠️ **설계·컨벤션의 근거는 이 repo에 없다.** "왜 OpenTofu인가", "왜 facade 패턴인가" 같은 질문은
`iac-module-library`의 `CLAUDE.md`·`docs/decisions.md`가 갖는다. 여기서 다시 쓰지 않는다.
문서 문체 규칙(em-dash 금지·이모지 7종·400줄 제한)은 아래 6절이 가리키는 스크립트로
**이식**되어 있다(이식한 이유는 그 스크립트가 이 repo 안에서 pre-commit 훅으로 즉시
실행돼야 하기 때문이다). 규칙 텍스트 자체의 SSOT는 여전히 module repo다.

**운영 절차 SSOT는 반대로 이 repo다.** hub/spoke를 세우고 걷어내는 순서, 자주 막히는 지점,
운영 런북은 아래 세 문서가 소유한다:

- [`docs/hub-lifecycle.md`](docs/hub-lifecycle.md): hub 구축·철거
- [`docs/spoke-lifecycle.md`](docs/spoke-lifecycle.md): spoke 구축·철거
- [`docs/runbooks.md`](docs/runbooks.md): 이미 선 환경 운영(접근·업그레이드·GitOps 상태 확인 등)

작업을 시작하기 전에 해당 절차 문서부터 읽는다. 이 CLAUDE.md는 그 문서들이 전제하는
"이 repo가 어떻게 조립되어 있는가"만 담는다.

## 1. 저장소 구조

```
bootstrap/            state 버킷 · OIDC provider · Role (IaC 밖, 사람이 스크립트로 실행)
live/hub/networking/   VPC (hub)
live/hub/tgw/          Transit Gateway (hub, networking과 분리된 state)
live/hub/eks/          EKS + workbench (hub)
live/dev/networking/   VPC + TGW attachment (spoke 첫 인스턴스)
live/dev/eks/          EKS + workbench + cross-account-trust-role (spoke)
.github/workflows/     배포 루트마다 워크플로 하나(plan은 push, apply/destroy는 workflow_dispatch)
docs/                  운영 절차 SSOT(0절) + 이 repo 고유 참조 문서
scripts/               teardown-verify.sh · argocd-seed.sh · validate-doc-conventions.py
```

같은 repo 안에서 `live/hub/*`와 `live/dev/*`는 **각자 별도 state**를 쓴다(같은 배포 루트
안의 다른 env). `live/hub/networking`과 `live/hub/tgw`·`live/hub/eks`도 서로 분리된 state다.
루트 간 결합은 `terraform_remote_state`가 아니라 **Name·태그 기반 `data` 조회**로만 한다.

## 2. 실행 모델

| 항목 | 규칙 |
|------|------|
| 엔진 | OpenTofu(`tofu`), Terraform이 아니다 |
| backend | S3 + `use_lockfile = true`. 버킷명은 git에 없다(GitHub 저장소 변수 `HUB_TF_STATE_BUCKET`/`DEV_TF_STATE_BUCKET` + 로컬 `backend.hcl`, 둘 다 git 밖) |
| state key | `<env>/<component>.tfstate` (예: `hub/tgw.tfstate`, `dev/networking.tfstate`) |
| 자격증명 | GitHub OIDC → 입구 Role(`*_AWS_ENTRY_ROLE_ARN`) → 실행 Role(`*_AWS_EXEC_ROLE_ARN`), 2단 체인 |
| plan → apply | plan을 workflow run 안에 저장해 사람이 요약을 읽고 **dispatch를 누르는 것 자체가 승인**이다(`pull_request` 트리거는 2026-08-03 의도적으로 제거) |
| 로컬에서 되는 것 | `init` + `validate`까지. **apply·destroy는 로컬에서 안 된다**(실행 Role이 입구 Role만 신뢰해 개인 IAM user는 관리자여도 `AccessDenied`) |

⚠️ **재시도할 때 `workflow run`을 새로 누르지 않는다.** 실패한 job이 apply라면 `gh run rerun
<run-id> --failed`로 **저장된 plan을 그대로** 재적용한다. 새 dispatch는 plan을 처음부터 다시
돌려 승인한 것과 다른 계획을 만든다.

## 3. 네이밍·태깅

`Name` 태그 포맷과 리소스 타입 약어는 `iac-module-library`의 `docs/naming/abbreviations/aws.md`가
SSOT다(임의 생성 금지). 이 repo에서 실제로 쓰는 값:

- `workload` = `demo`(고정, `live/hub`·`live/dev` 모두 반드시 동일해야 한다)
- `env` = `hub` 또는 `dev`(spoke 첫 인스턴스), `region` = `ap-northeast-2`(`an2`)
- 예: `eks-demo-hub-an2-main-01`, `eks-demo-dev-an2-main-01`

`Name`은 모듈이 `naming` 객체를 받아 합성한다. 배포 루트(이 repo)가 약어를 직접 조합하지 않는다.

## 4. 로컬 게이트 (git hook)

```
pre-commit: 문서 변경 시 scripts/validate-doc-conventions.py → tofu fmt -check → tflint → trivy config
pre-push:   live/**/*.tf 변경 시 각 루트 tofu validate (모듈 계약 테스트는 module repo가 담당, 여기 없음)
```

clone마다 1회 활성화: `git config core.hooksPath .githooks`. 우회(`--no-verify`)는 긴급 시에만,
사유를 커밋 메시지에 남긴다.

## 5. 브랜치·PR 규칙

| 변경 대상 | 경로 |
|-----------|------|
| **`.tf` · `.github/workflows/`** | **브랜치 → PR** |
| **문서 전용(`docs/*.md`·`CLAUDE.md`·`.omc/notepad.md`)** | **`main` 직접 커밋** |

기준은 module repo와 같다: *"CI가 머지 전에 막아야 하는가"* 하나뿐이다. 각 워크플로는
`push: branches: [main]`에도 plan까지 돌므로 "PR이어야 CI가 돈다"는 성립하지 않는다. 차이는
**깨진 것이 main에 들어가기 전에 걸리느냐**뿐이고, 문서 전용 변경엔 main을 깨뜨릴 산출물이 없다.

## 6. 문서 작성 규칙

`docs/*.md`·`README.md`·`AGENTS.md`·이 파일은 `python3 scripts/validate-doc-conventions.py`로
검증한다(pre-commit이 staged 파일에 자동 실행). 기계로 잡는 4가지: 문서 간 절 번호 인용 금지,
이모지는 `✅⏳❌⚠️⛔🔴🔑` 7종만, 문서당 400줄 제한, em-dash(유니코드 U+2014) 금지. 나머지
문체 규칙 전문의 SSOT는 0절의 `iac-module-library` `docs/conventions.md`다.

## 7. 새 리소스·모듈 인자를 쓰기 전에

이 repo는 모듈 내부를 고치지 않지만, 루트 `main.tf`가 모듈에 넘기는 변수·참조하는 출력은
추정하지 않는다: `mcp__opentofu__get-module-details`(`namespace`·`name`·`target`)로 실제
계약을 확인하거나, `live/*/.terraform/modules/`의 다운로드된 실물 소스를 연다.

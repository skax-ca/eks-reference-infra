# scripts: 운영 절차 스크립트

**읽는 사람**: 철수 검증을 실행하거나 이 저장소의 셸·문서 게이트를 손보는 사람.

| 스크립트 | 무엇을 하는가 | 설계 SSOT |
|---|---|---|
| `teardown-verify.sh` | 철수 후 잔존물 검사(읽기 전용). 지우지 않고 남은 것만 찾는다 | `docs/hub-lifecycle.md`, `docs/spoke-lifecycle.md` |
| `validate-doc-conventions.py` | 이 저장소 문서(`docs/*.md`·`README.md`·`AGENTS.md`·`CLAUDE.md`)의 작성 규칙 검사 | `.githooks/pre-commit` |
| `validate-comment-conventions.py` | `.tf`·셸·검사기·훅·워크플로·`dependabot.yml`의 주석에서 외부 참조와 이력 서술 검사. 적용 범위는 검사기 자신이 갖는다 | `.githooks/pre-commit`(해당 파일 staged 시)와 `verify.yml` |
| `report-module-tag-drift.py` | 루트들이 같은 모듈을 다른 태그로 소싱하는지 보고. ⚠️ 검사기가 아니라 보고기다 — 갈려 있어도 실패시키지 않고 Summary에 표만 남긴다 | `verify.yml` |

⚠️ 모든 스크립트는 환경값을 하드코딩하지 않는다. 대상 계정·클러스터 이름 같은 값은 전부
환경변수나 인자로 받는다.

---

## `teardown-verify.sh`

철수(destroy) 뒤에 실제로 아무것도 남지 않았는지 확인하는 읽기 전용 스크립트다. 아무것도
지우지 않는다. 삭제는 사람이 `tofu destroy`로 한다.

```bash
WORKLOAD=demo ENVIRONMENT=hub AWS_PROFILE=team ./scripts/teardown-verify.sh
```

비용이 계속 나는 자원(NAT Gateway, EC2, EBS, Elastic IP, 로드밸런서, EKS 컨트롤 플레인)부터
검사하고, 이어서 삭제를 막는 자원(ENI, VPC), 마지막으로 보존 요건을 확인해야 하는 자원
(CloudWatch 로그 그룹)을 본다. 대상 계정이 공용일 수 있으므로 모든 조회를 `WORKLOAD`/
`ENVIRONMENT` 태그로 좁힌다. 태그가 없는 자원은 이 스크립트가 찾지 못하므로, 콘솔에서
VPC 기준으로 한 번 더 확인하는 것이 안전하다.

종료 코드: `0` = 잔존물 없음, `1` = 잔존물 있음, `2` = 실행 불가.

## 셸 게이트: `bash -n` + `shellcheck`

`.githooks/pre-commit`이 staged된 `bootstrap/*.sh`·`scripts/*.sh`·`.claude/skills/**/*.sh`에
`bash -n`(문법)과 `shellcheck -x`(인용·확장·종료코드)를 돌린다. 둘 다 통과해야 커밋이 선다.

```bash
brew install shellcheck gitleaks   # clone마다 1회. 없으면 훅이 즉시 실패한다
```

`verify.yml`이 같은 명령을 PR·main push에서 다시 돈다(shellcheck 버전을 로컬과 같게 핀한다).
배포 워크플로는 루트별 트리거라 `.sh`만 바뀐 커밋은 어느 배포 워크플로도 돌리지 않지만,
`verify.yml`은 경로 필터가 없어 그 커밋도 본다.

`-x`는 `source`된 파일을 따라간다. 각 스크립트의 `# shellcheck source=` 지시자가 저장소 루트
기준 경로를 주고 훅은 항상 루트에서 돌기 때문에, 그 경로가 그대로 맞는다.

의도된 패턴은 지적이 아니라 **사유를 적은 `disable` 지시자**로 남긴다. `--tags $(tag_args_iam …)`의
비인용은 태그를 인자 여러 개로 흘리려는 것이고, 인용하면 aws CLI가 거부한다. `config.sh`의
변수들은 `source`하는 쪽에서 쓰이므로 한 파일만 보는 검사기에는 미사용으로 보인다.
⚠️ 설명 주석을 `# shellcheck`로 시작하지 않는다 — 검사기가 그 줄을 지시자로 파싱해 실패한다.

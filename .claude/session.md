# Session — eks-reference-infra

## 지난 세션 (2026-09-16)
bootstrap 실행 Role `--description`의 한글을 영문으로 고쳤다(IAM은 Latin-1까지만 받는다).
description은 create-role 때만 들어가 재실행이 `changed=0`으로 결함을 가렸으므로, `config.sh`에
기대 문자열을 두고 `bootstrap.sh`가 `update-role`로 수렴시키고 `verify.sh`가 drift로 잡게 했다.
team·asset 두 계정에서 verify(drift 1) → bootstrap(변경 1) → bootstrap(변경 0) → verify(drift 없음)로
확인했고, 실물 Role에 남아 있던 `D27-1 pattern` 문구도 이때 지웠다(337f0ce).
`live/dev/networking/main.tf`의 `aws_ram_resource_share_accepter` `removed` 블록은 dev state가
리소스 0개라 no-op이어서 지웠고, 그 블록을 가리키던 `docs/spoke-lifecycle.md`·`deploy-dev-network.yml`
3곳을 ⛔ 주석 자리로 고쳤다(PR #43). 지난 목록 1번(`deletion_protection` 복원)은 4곳 인라인 주석이
이미 적고 있어서, 4번(module repo grep 절차)은 iac-module-library 세션이 4개 repo를 묶어 다루기로
해서 뺐다.
세션을 iac-module-library에서만 열기로 해 CLAUDE.md를 123줄 → 24줄로 줄였다(56dda5f: 전역 규칙
제거본 96줄, ca131b6: 값과 문서 좌표만). 뺀 규칙 문장(실행 모델·게이트·네이밍 규칙·모듈 계약
확인·SSOT 지도)은 module repo CLAUDE.md의 「배포 루트 공통」으로 올린다. 원문은
`git show 56dda5f:CLAUDE.md`. hub는 여전히 전부 destroy 상태라 main push plan은 `hub/tgw`만
성공한다(정상).

## 다음 할 일
- [ ] iac-module-library CLAUDE.md에 「배포 루트 공통」을 만든 뒤 이 repo CLAUDE.md 머리말의 절 이름을 맞춘다
- [ ] 이 repo의 `.claude/session.md` 거취(module repo session.md로 통합 후 삭제)를 module repo 설계에서 정한다

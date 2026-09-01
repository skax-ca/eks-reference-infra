---
name: notepad-sync
description: 이 프로젝트(eks-reference-infra)의 .omc/notepad.md·project-memory.json 관리 절차. 전역 session-start/session-end 스킬이 3단계(세션 태스크 확인/메모리 갱신)에서 이 스킬이 있으면 호출하도록 위임한다. OMC가 이 머신에서 비활성 상태(~/.claude/.omc-enabled 없음)면 조용히 건너뛴다.
---

# Notepad Sync (project-scoped)

이 프로젝트는 `iac-module-library`와 **동일한** OMC notepad 3단 구조(**Priority** 포인터·500자
이내 / **Working** 세션 서술·7일 자동 소멸 / **MANUAL** 영구 아카이브·자동 로드 안 됨)와
`project-memory.json`(구조화 영구 사실)을 쓴다(2026-08-19 전환 — 이전에는 이 repo만의 날짜별
prepend 방식을 썼으나, iac-module-library와 다른 메커니즘을 유지할 이유가 없어 통일했다).
세션 종료 시 "무엇을 어디에 저장할지" 판단은 **OMC가 이미 제공하는
`oh-my-claudecode:remember` 스킬에 위임**한다 — 그 판단 로직을 여기서 다시 만들지 않는다. 이 파일은
그 위임 전 가드와, `remember`가 모르는 이 repo 고유의 제약만 얹는다.

## 0. 가드 — OMC가 이 머신에서 꺼져 있으면 전부 건너뛴다

`~/.claude/.omc-enabled` 파일이 없으면 (또는 `oh-my-claudecode:remember` 스킬이 안 보이면)
아래 1~2 절 전부 건너뛰고 다음 한 줄만 안내한다: "이 머신은 OMC 비활성화 상태라 프로젝트 컨텍스트
확인/저장을 생략합니다(`touch ~/.claude/.omc-enabled`로 활성화 가능)." 에러로 취급하지 않는다 —
이 프로젝트가 OMC를 쓰기로 한 것과, 지금 이 머신에서 OMC를 켰는지는 별개다.

## ⛔ 2026-09-01, `mcp__t__notepad_*`/`mcp__t__project_memory_*` 도구 사용을 전면 중단

원인: `iac-module-library`(이 repo가 모듈을 소싱하는 저장소)에서 이 MCP 도구가 "읽기"조차
내부적으로 프로젝트를 재스캔해 `project-memory.json`의 서술형 필드를 빈 스키마로 덮어쓰거나,
`add_note`가 20개 FIFO로 경고 없이 오래된 항목을 삭제하거나, git merge/pull 직후 stale 캐시로
파일을 다중 재작성하는 부수효과가 여러 차례 실측됐다(표준 Read/Edit 도구엔 없는 숨은 로직).
Claude Code 공식 문서(`permissions.md`) 확인 결과 `.claude/settings.json`의 `permissions.deny`에
파라미터 없는 도구명 glob을 등록하면 그 도구가 Claude의 도구 목록에서 완전히 제거된다 — 그래서
이 두 도구군(읽기·쓰기 전부)을 등록해 차단했다. 상세 리서치·근거는 `iac-module-library` 커밋
`35d7c2b`와 그 repo `project-memory.json`의 `mcp-tooling-fix` 카테고리 참조.

⚠️ **이 repo 자신의 과거 사고와의 관계**: 바로 아래 세션 종료 절차가 원래 "Edit로 직접 쓰지 말고
반드시 MCP 쓰기 도구를 통해서만 쓰라"고 했던 이유는 2026-08-14에 Edit로 `.omc/notepad.md` 상단에
직접 prepend하다가 Priority Context가 200KB까지 비대화된 사고 때문이었다 — 그런데 그 사고의
근본원인은 "Priority Context는 전체 교체, Working Memory는 최신 항목만 최상단에 추가"라는 규율을
사람/에이전트가 안 지킨 것이었지, MCP 도구 자체의 결함이 아니었다. 이번 전환으로 그 규율을
강제해주던 도구가 사라졌으므로, **아래 세션 종료 절차의 "전체 교체"·"최상단 추가" 지침을 Edit로
쓸 때 수동으로 반드시 지킬 것** — 자동으로 막아주는 장치가 없다.

## 세션 시작 시 (session-start 3번에서 호출됨, 가드 통과 후)

1. `Read`로 `.omc/notepad.md`를 열어 `## Priority Context`(또는 동일한 역할의) 섹션을 사용자에게
   보여준다.
2. `Read`로 `.omc/project-memory.json`을 열어 `customNotes`의 `open-items` 카테고리 중 최신
   항목들로 미결 사항을 확인한다.
3. 같은 `.omc/notepad.md`의 Working Memory 섹션에 최근 7일 내 세션 서술이 있으면 함께 보여준다.
4. Priority Context가 눈대중으로 500자를 넘어 보이면 — 정리하지 말고 사용자에게 먼저 알린다.

## 세션 종료 시 (session-end 2번에서, 커밋 전에 호출됨, 가드 통과 후)

1. **`oh-my-claudecode:remember` 스킬을 호출**해 이번 세션의 발견 사항을 분류·저장시킨다
   (project memory / notepad priority / notepad working / docs 중 어디로 갈지는 그 스킬이 판단한다).
2. `remember`가 모르는, 이 repo만의 제약을 그 판단에 추가로 적용한다:
   - **`.omc/notepad.md`·`.omc/project-memory.json` 전부 `Edit`/`Read` 도구로 직접 다루는 것이
     유일한 경로다**(2026-09-01부터 MCP 쓰기 도구는 `permissions.deny`로 아예 제거됨, 위 절 참조).
   - ⛔ **Priority Context는 `Edit`로 전체 교체한다(append 아님), 500자 이내 유지.** Working
     Memory는 최신 항목을 상단에 추가한다. 위 절에 적었듯 이 두 규칙을 어기면 2026-08-14와 같은
     비대화 사고가 재발한다 — 이번엔 도구가 막아주지 않으므로 쓴 뒤 반드시 `git diff`로 의도한
     변경만 있는지 확인한다.
   - `docs/*.md`(`docs/deployment-facts.md` 등)에는 날짜·사건 서술을 쓰지 않는다(`CLAUDE.md`
     「0. 설계는 이 repo에 없다」가 모듈 repo `docs/conventions.md` §8을 그대로 적용) —
     `remember`가 "docs"를 저장 후보로 제안해도 서술형 내용이면 notepad로 돌린다.
   - `project-memory.json`은 `.gitignore` 화이트리스트로 git 커밋 대상이다(notepad.md와 함께
     크로스 머신 SSOT) — 이 머신에만 유효한 임시 정보는 넣지 않는다.
3. 이 단계가 끝난 뒤에만 session-end 3번(커밋)으로 넘어간다 — 위 변경분이 그 커밋에 함께 실려야 한다.

## opencode 세션

`.opencode/plugins/notepad.ts`가 이 repo 안에서 같은 3단 구조 툴(`notepad_read`/
`notepad_write_priority`/`notepad_write_working`/`notepad_write_manual`)을 제공한다
(iac-module-library의 것과 로직이 동일 — 구조가 같아졌으므로 그대로 이식했다). 이 플러그인은
Claude Code의 MCP 서버가 아니라 이 repo 프로세스 안에서 직접 파일을 다루는 별개 코드 경로라
위에서 차단한 `permissions.deny`의 영향을 받지 않는다 — 이 세션이 겪은 버그가 이 플러그인에도
있는지는 별도로 확인이 필요하다(미검증, iac-module-library도 아직 확인 안 함).

---
name: notepad-sync
description: 이 프로젝트(iac-reference-infra)의 .omc/notepad.md 관리 절차. 전역 session-start/session-end 스킬이 3단계(세션 태스크 확인/메모리 갱신)에서 이 스킬이 있으면 호출하도록 위임한다. OMC가 이 머신에서 비활성 상태(~/.claude/.omc-enabled 없음)면 조용히 건너뛴다.
---

# Notepad Sync (project-scoped)

이 프로젝트는 `iac-module-library`와 **다른 notepad 메커니즘**을 쓴다 — OMC의 3단 구조
(Priority/Working/Manual)가 아니라, 파일 하나(`.omc/notepad.md`)에 날짜별 `##` 항목을 최상단
prepend하는 단순 구조다. 파일 하단에 `## Priority Context` 섹션이 별도로 있다(자주 안 바뀜,
자동 로드 장치 없음 — 세션 시작 시 사람이/스킬이 직접 보여줘야 한다).

## 0. 가드 — OMC가 이 머신에서 꺼져 있으면 전부 건너뛴다

`~/.claude/.omc-enabled` 파일이 없으면 (또는 `oh-my-claudecode:remember` 스킬이 안 보이면)
아래 1~2절 전부 건너뛰고 다음 한 줄만 안내한다: "이 머신은 OMC 비활성화 상태라 프로젝트 컨텍스트
확인/저장을 생략합니다(`touch ~/.claude/.omc-enabled`로 활성화 가능)." 에러로 취급하지 않는다.

## ⛔ `mcp__t__notepad_*`/`mcp__t__project_memory_*`(OMC 전역 브리지)를 이 repo에 쓰지 않는다

이 툴들은 `workingDirectory` 파라미터를 받지만, OMC 소스(`dist/lib/worktree-paths.js`
`validateWorkingDirectory`)를 실측 확인한 결과 **의도된 보안 경계**다: `trustedRoot =
getGitTopLevel(process.cwd())`이고, 이 `process.cwd()`는 **MCP 서버 프로세스가 Claude Code
세션 시작 시점에 스폰될 때 고정**된다. 그래서 `iac-module-library`를 프로젝트 루트로 연
세션에서는 `workingDirectory`에 이 repo 경로를 아무리 넘겨도 다른 git worktree라 거부되고
조용히 `iac-module-library`에 쓴다(2026-08-19 실측: 이 repo용 세션 요약이
`iac-module-library/.omc/notepad.md`에 잘못 들어가 6중복까지 갔던 사고 — `git checkout`으로
복구). **버그가 아니라 세션당 한 프로젝트로 격리하는 설계**이므로, 이 repo를 Claude Code
프로젝트 루트로 직접 열지 않는 한 그 브리지로는 원천적으로 이 repo에 쓸 수 없다.

## ✅ 이 repo를 프로젝트 루트로 연 세션에서는 전용 MCP 서버를 쓴다 (1순위)

`.mcp.json`에 등록된 `notepad-local` 서버(`.mcp/notepad-server.ts`, 이 repo 전용, 2026-08-19
신설)가 Claude Code 세션에 3툴을 제공한다:
- `mcp__notepad-local__notepad_read(section)` — `recent`(최근 2항목, 기본)·`priority`(하단
  Priority Context)·`all`
- `mcp__notepad-local__notepad_write_session(title, content)` — 최상단에
  `## <날짜> — <title>` 항목 prepend
- `mcp__notepad-local__notepad_write_priority(content)` — `## Priority Context` 섹션 본문만
  교체(500자 제약 없음)

⚠️ **처음 이 repo를 열면 승인 프롬프트가 뜬다** — Claude Code가 project-scoped `.mcp.json`
서버를 보안상 대화형으로 승인받는다(공식 문서 확인). `claude` 인터랙티브 세션에서 한 번
승인하면 이후 세션은 자동 연결된다. 승인 전이거나 서버가 안 붙었으면(`/mcp`로 상태 확인)
아래 "Edit 직접 prepend" 대체 경로로 내려간다.

로직(`readSection`/`prependSession`/`replacePriority`)은 `.mcp/notepad-core.ts` 하나를
opencode 플러그인과 이 MCP 서버 양쪽이 공유한다(중복 없음, drift 없음). 문자열 삽입/치환만
하고 파싱 후 전체 재조립을 하지 않으므로 하단 아카이브를 파괴하지 않는다 — 무손실은
`.mcp/notepad-core.test.ts`가 실제 notepad.md로 검증(`cd .mcp && bun test`).

## 대체 경로 — MCP 서버가 아직 안 붙었으면 Edit 직접 prepend

MCP 서버 승인 전이거나 세션이 이 repo를 프로젝트 루트로 열지 않은 경우(예:
`iac-module-library` 세션에서 이 repo 작업만 잠깐 하는 경우)에는 `Edit` 툴로
`.omc/notepad.md` 최상단(`# Notepad — iac-reference-infra` 헤더 바로 아래)에 직접
prepend한다. 이 repo에는 `iac-module-library`식 "Edit 직접 prepend 금지" 규칙이 적용되지
않는다 — 그 규칙이 막으려던 MCP 브리지 문제 자체가 이 repo에서 별도로 해결됐기 때문이다.

opencode 세션에서는 `.opencode/plugins/notepad.ts`의 커스텀 툴(`notepad_read`/
`notepad_write_session`/`notepad_write_priority`, 이름은 위 MCP 서버와 동일)이 1순위다 —
같은 `.mcp/notepad-core.ts`를 임포트하므로 동작이 완전히 같다. 툴이 로드 안 됐으면(opencode
재시작 필요) Edit 직접 prepend로 대체한다.

## 세션 시작 시 (session-start 3번에서 호출됨, 가드 통과 후)

1. **이 repo가 프로젝트 루트면** `mcp__notepad-local__notepad_read(section="recent")`와
   `notepad_read(section="priority")`로 최근 항목·Priority Context를 읽는다. 아니면 `Read`로
   `.omc/notepad.md` 상단 몇 개 항목 + 하단 `## Priority Context`를 직접 읽는다
   (`grep -n "^## "`로 위치를 먼저 찾으면 빠르다).
2. 읽은 내용을 사용자에게 보여준다.
3. 이 repo는 `project-memory.json`을 쓰지 않는다 — notepad.md 하나가 SSOT다. 미결 항목은
   notepad 항목 본문의 "다음 세션 시작 시 착수 후보" 같은 절에서 직접 찾는다.

## 세션 종료 시 (session-end 2번에서, 커밋 전에 호출됨, 가드 통과 후)

1. **`oh-my-claudecode:remember` 스킬을 호출**해 이번 세션의 발견 사항을 분류시킨다 — 단,
   그 스킬이 "project memory"나 "notepad priority/working (OMC 전역 브리지 경유)"를 제안해도
   위 함정 때문에 **이 repo에서는 실행 경로를 아래로 대체**한다:
   - "notepad에 기록" → `notepad_write_session(title, content)`(MCP 서버 붙어 있으면) 또는
     `Edit`로 최상단에 날짜별 `## <날짜> — <제목>` 항목 prepend(기존 항목 형식을 그대로
     따른다 — 배경 한 줄, 무엇을 했는지, 다음 착수 후보).
   - "project memory에 기록" → 이 repo엔 그런 파일이 없다. notepad 항목 본문에 같이 적는다.
   - "Priority Context 갱신" → `notepad_write_priority(content)` 또는 `Edit`로 파일 하단
     `## Priority Context` 섹션 직접 수정(전체 교체가 아니라 관련 절만 갱신 — 500자 제약 없음).
2. `docs/*.md`(`docs/deployment-facts.md` 등)에는 날짜·사건 서술을 쓰지 않는다(`CLAUDE.md`
   「0. 설계는 이 repo에 없다」가 모듈 repo `docs/06-conventions.md` §8을 그대로 적용) —
   `remember`가 "docs"를 제안해도 서술형 내용이면 notepad로 돌린다. `docs/deployment-facts.md`는
   "값이 아니라 어디에 있는지"·"현재 형상"만 적는다(포인터·현재 사실, 세션 서사 아님).
3. notepad.md가 커질수록(`wc -l .omc/notepad.md`로 눈대중 확인) `iac-module-library`가
   200KB+까지 부풀었던 전례를 참고해 사용자에게 정리 필요성을 알린다 — 2026-08-19 기준
   ~100KB. ⚠️ **실제 아카이브/정리 로직은 아직 없다** — 이 절이 하는 건 경고뿐이다. 정리가
   필요해지면 별도로 설계한다(예: N개월 지난 항목을 별도 아카이브 파일로 이동).
4. 이 단계가 끝난 뒤에만 session-end 3번(커밋)으로 넘어간다 — 위 변경분이 그 커밋에 함께 실려야
   한다. `.omc/notepad.md`는 이 repo `.gitignore`에서 `!/.omc/notepad.md`로 명시적으로 커밋
   대상이다(다른 `.omc/*`는 제외).

## 알려진 한계

- `.mcp/`·`.opencode/`는 각자 `node_modules`가 필요하다(`cd .mcp && bun install`,
  `cd .opencode && bun install`) — repo를 새로 clone하면 한 번씩 실행해야 한다.
- Claude Code 세션에서는 opencode 플러그인처럼 "Edit로 직접 편집하면 차단"하는 훅이 없다
  (MCP 프로토콜 자체가 다른 툴 호출을 가로챌 수 없다 — opencode의 `tool.execute.before`는
  opencode 전용 플러그인 API다). 필요해지면 Claude Code `PreToolUse` 훅(`.claude/settings.json`)
  으로 별도 구현할 수 있다 — 아직 안 만들었다.

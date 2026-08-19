---
name: notepad-sync
description: 이 프로젝트(iac-reference-infra)의 .omc/notepad.md 관리 절차. 전역 session-start/session-end 스킬이 3단계(세션 태스크 확인/메모리 갱신)에서 이 스킬이 있으면 호출하도록 위임한다. OMC가 이 머신에서 비활성 상태(~/.claude/.omc-enabled 없음)면 조용히 건너뛴다.
---

# Notepad Sync (project-scoped)

이 프로젝트는 `iac-module-library`와 **다른 notepad 메커니즘**을 쓴다 — OMC의 3단 구조
(Priority/Working/Manual)와 `mcp__t__notepad_*` 브리지 툴이 **아니라**, 파일 하나
(`.omc/notepad.md`)에 날짜별 `##` 항목을 최상단 prepend하는 단순 구조다(원래
opencode 플러그인(`.opencode/plugins/notepad.ts`)용으로 설계됨). 파일 하단에
`## Priority Context` 섹션이 별도로 있다(자주 안 바뀜, 자동 로드 장치 없음 — 세션 시작 시
사람이/스킬이 직접 보여줘야 한다).

## 0. 가드 — OMC가 이 머신에서 꺼져 있으면 전부 건너뛴다

`~/.claude/.omc-enabled` 파일이 없으면 (또는 `oh-my-claudecode:remember` 스킬이 안 보이면)
아래 1~2절 전부 건너뛰고 다음 한 줄만 안내한다: "이 머신은 OMC 비활성화 상태라 프로젝트 컨텍스트
확인/저장을 생략합니다(`touch ~/.claude/.omc-enabled`로 활성화 가능)." 에러로 취급하지 않는다.

## ⛔ 가장 중요한 함정 — `mcp__t__notepad_*`/`mcp__t__project_memory_*` 툴을 이 repo에 쓰지 않는다

이 툴들은 `workingDirectory` 파라미터를 받지만 **실제로는 무시하고 항상
`iac-module-library`(OMC가 설치된 원 프로젝트)의 notepad·project-memory에 쓴다** — 다른
프로젝트를 대상으로 지정해도 에러 없이 조용히 엉뚱한 파일에 쓴다(2026-08-19 실측: 이 repo용으로
쓴 세션 요약이 `iac-module-library/.omc/notepad.md`에 잘못 들어갔고, 그 시도가 기존 5중 중복
버그와 겹쳐 항목이 6중복까지 갔던 사고가 있었다 — `git checkout`으로 복구).

**Claude Code 세션에서 이 repo의 notepad를 갱신할 때는 `Edit` 툴로 `.omc/notepad.md`
최상단(`# Notepad — iac-reference-infra` 헤더 바로 아래)에 직접 prepend한다.** 이 repo에는
`iac-module-library`식 "Edit 직접 prepend 금지" 규칙이 **적용되지 않는다** — 애초에 그 규칙이
막으려던 MCP 브리지 자체가 이 repo에서 동작하지 않기 때문이다.

opencode 세션에서는 `.opencode/plugins/notepad.ts`의 커스텀 툴이 1순위다 — 그 플러그인은 이 repo
안에서 직접 동작하므로 위 MCP 브리지 문제가 없다. 이 repo 전용 3툴(iac-module-library의
`notepad_write_working`과 이름·동작이 다르다 — 이 repo는 3단 구조가 아니므로):
- `notepad_read(section)` — `recent`(최근 2항목)·`priority`(하단 Priority Context)·`all`
- `notepad_write_session(title, content)` — 최상단에 `## <날짜> — <title>` 항목 prepend
- `notepad_write_priority(content)` — `## Priority Context` 섹션 본문만 교체(500자 제약 없음)

세 툴 모두 "파싱 후 전체 재조립"을 하지 않고 문자열 삽입/치환만 하므로 하단 아카이브를 파괴하지
않는다(무손실은 `plugins/notepad.test.ts`가 실제 notepad.md로 검증). 플러그인은 `.omc/notepad.md`
직접 `edit`/`write`를 가드로 차단한다. 툴이 로드 안 됐으면(opencode 재시작 필요) Claude Code와
같은 방식(Edit 직접 prepend)으로 대체한다.

## 세션 시작 시 (session-start 3번에서 호출됨, 가드 통과 후)

1. `.omc/notepad.md`를 `Read`로 읽는다(파일 전체 또는 최소 상단 최근 항목 몇 개 + 하단
   `## Priority Context` 섹션 — `grep -n "^## "`로 위치를 먼저 찾으면 빠르다).
2. 최상단 최근 항목(들)과 `## Priority Context` 내용을 사용자에게 보여준다.
3. 이 repo는 `project-memory.json`을 쓰지 않는다 — notepad.md 하나가 SSOT다. 미결 항목은
   notepad 항목 본문의 "다음 세션 시작 시 착수 후보" 같은 절에서 직접 찾는다.

## 세션 종료 시 (session-end 2번에서, 커밋 전에 호출됨, 가드 통과 후)

1. **`oh-my-claudecode:remember` 스킬을 호출**해 이번 세션의 발견 사항을 분류시킨다 — 단,
   그 스킬이 "project memory"나 "notepad priority/working (MCP 툴 경유)"를 제안해도 위 함정
   때문에 **이 repo에서는 실행 경로를 아래로 대체**한다:
   - "notepad에 기록" → `Edit`로 `.omc/notepad.md` 최상단에 날짜별 `## <날짜> — <제목>` 항목
     prepend(기존 항목의 형식을 그대로 따른다 — 배경 한 줄, 무엇을 했는지, 다음 착수 후보).
   - "project memory에 기록" → 이 repo엔 그런 파일이 없다. notepad 항목 본문에 같이 적는다.
   - "Priority Context 갱신" → 파일 하단 `## Priority Context` 섹션을 `Edit`로 직접 수정
     (전체 교체가 아니라 관련 절만 갱신 — 이 섹션은 자주 안 바뀌고 상당히 길다, 500자 제약 없음).
2. `docs/*.md`(`docs/deployment-facts.md` 등)에는 날짜·사건 서술을 쓰지 않는다(`CLAUDE.md`
   「0. 설계는 이 repo에 없다」가 모듈 repo `docs/06-conventions.md` §8을 그대로 적용) —
   `remember`가 "docs"를 제안해도 서술형 내용이면 notepad로 돌린다. `docs/deployment-facts.md`는
   "값이 아니라 어디에 있는지"·"현재 형상"만 적는다(포인터·현재 사실, 세션 서사 아님).
3. notepad.md가 커질수록(`wc -l .omc/notepad.md`로 눈대중 확인) `iac-module-library`가
   200KB+까지 부풀었던 전례를 참고해 사용자에게 정리 필요성을 알린다 — 이 repo는 아직 그
   규모가 아니지만(2026-08-19 기준 ~90KB), 미리 주기적으로 언급한다.
4. 이 단계가 끝난 뒤에만 session-end 3번(커밋)으로 넘어간다 — 위 변경분이 그 커밋에 함께 실려야
   한다. `.omc/notepad.md`는 이 repo `.gitignore`에서 `!/.omc/notepad.md`로 명시적으로 커밋
   대상이다(다른 `.omc/*`는 제외).

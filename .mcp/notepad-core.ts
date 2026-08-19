// 이 repo의 notepad 구조는 iac-module-library와 다르다.
//   - iac-module-library: 정형 3단(## Priority Context / ## Working Memory / ## MANUAL).
//   - 이 repo: 헤더(# Notepad — iac-reference-infra) 아래로 날짜별 `## <날짜> — <제목>`
//     항목이 최신순으로 쌓이고, `## Priority Context`가 파일 "중간"에 끼어 있으며 그 아래로
//     과거 아카이브가 이어진다(정형화돼 있지 않고 중복 항목도 있다).
//   → 그래서 아래 함수들은 절대 "파싱 후 전체 재조립"을 하지 않는다. 문자열 삽입/치환만 하고
//     나머지 파일 내용은 원본 그대로 보존한다(1300줄+ 아카이브 파괴 방지).
//
// 이 파일은 순수 함수만 담는다(파일 IO 없음, 프레임워크 의존 없음) — 그래서 opencode
// 플러그인(.opencode/plugins/notepad.ts)과 Claude Code용 MCP 서버(.mcp/notepad-server.ts)
// 양쪽이 이 하나를 공유한다. 로직을 두 곳에 복제하면 한쪽만 고치는 drift가 생긴다.

export const HEADER = "# Notepad — iac-reference-infra"
export const PRIORITY_HEADING = "## Priority Context"

export function dateStamp(d: Date = new Date()): string {
  const p = (n: number) => String(n).padStart(2, "0")
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`
}

// 최상위(## ) 헤딩의 시작 오프셋 목록. 정규식 없이 라인 스캔으로 안전하게 구한다.
export function topHeadingOffsets(text: string): { title: string; start: number }[] {
  const out: { title: string; start: number }[] = []
  let offset = 0
  for (const line of text.split("\n")) {
    if (line.startsWith("## ")) out.push({ title: line.slice(3).trim(), start: offset })
    offset += line.length + 1 // +1 = "\n"
  }
  return out
}

function priorityIndex(headings: { title: string }[]): number {
  return headings.findIndex((h) => `## ${h.title}` === PRIORITY_HEADING)
}

export type Section = "recent" | "priority" | "all"

export function readSection(text: string, section: Section): string {
  if (section === "all") return text
  const headings = topHeadingOffsets(text)
  if (headings.length === 0) return "[항목 없음]"

  if (section === "priority") {
    const idx = priorityIndex(headings)
    if (idx < 0) return "[Priority Context 섹션을 찾지 못함]"
    const end = idx + 1 < headings.length ? headings[idx + 1].start : text.length
    return text.slice(headings[idx].start, end).trim()
  }

  // recent: 헤더 다음 첫 최상위 항목부터 최대 2개 블록(Priority Context 위까지).
  const pIdx = priorityIndex(headings)
  const take = pIdx < 0 ? Math.min(2, headings.length) : Math.min(2, pIdx)
  if (take === 0) return "[최근 항목 없음 — Priority Context가 최상단]"
  const end = take < headings.length ? headings[take].start : text.length
  return text.slice(headings[0].start, end).trim()
}

export function prependSession(text: string, title: string, content: string, date = dateStamp()): string {
  const block = `## ${date} — ${title}\n\n${content}\n\n`
  const headings = topHeadingOffsets(text)
  if (headings.length === 0) {
    const headerEnd = text.indexOf(HEADER)
    const insertAt = headerEnd >= 0 ? headerEnd + HEADER.length : 0
    const before = text.slice(0, insertAt).replace(/\n*$/, "\n\n")
    const after = text.slice(insertAt).replace(/^\n*/, "")
    return `${before}${block}${after}`
  }
  // 첫 최상위 항목 앞에 삽입 = 나머지는 그대로 뒤로 밀림(재조립 없음).
  const at = headings[0].start
  return `${text.slice(0, at)}${block}${text.slice(at)}`
}

export function replacePriority(text: string, content: string): string {
  const headings = topHeadingOffsets(text)
  const idx = priorityIndex(headings)
  if (idx < 0) throw new Error("Priority Context 섹션을 찾지 못함 — 수동 확인 필요")
  const start = headings[idx].start
  const end = idx + 1 < headings.length ? headings[idx + 1].start : text.length
  const replacement = `${PRIORITY_HEADING}\n\n${content}\n\n`
  return `${text.slice(0, start)}${replacement}${text.slice(end)}`
}

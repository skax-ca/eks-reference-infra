import { type Plugin, tool } from "@opencode-ai/plugin"
import { readFile, writeFile } from "node:fs/promises"
import { join } from "node:path"

// ⚠️ 이 repo의 notepad 구조는 iac-module-library와 다르다.
//   - iac-module-library: 정형 3단(## Priority Context / ## Working Memory / ## MANUAL).
//   - 이 repo: 헤더(# Notepad — iac-reference-infra) 아래로 날짜별 `## <날짜> — <제목>`
//     항목이 최신순으로 쌓이고, `## Priority Context`가 파일 "중간"에 끼어 있으며 그 아래로
//     과거 아카이브가 이어진다(정형화돼 있지 않고 중복 항목도 있다).
//   → 그래서 이 플러그인은 절대 "파싱 후 전체 재조립"을 하지 않는다. 아래 순수 코어 함수들이
//     문자열 삽입/치환만 하고 나머지 파일 내용은 원본 그대로 보존한다(1300줄+ 아카이브 파괴 방지).
//   순수 코어(prependSession / replacePriority / readSection)는 파일 IO 없이 문자열→문자열이라
//   단위 테스트가 쉽다(plugins/notepad.test.ts).

export const HEADER = "# Notepad — iac-reference-infra"
export const PRIORITY_HEADING = "## Priority Context"

const notepadPath = (directory: string) => join(directory, ".omc", "notepad.md")

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

// ── 순수 코어 (문자열 → 문자열, IO 없음) ─────────────────────────────────

export function readSection(text: string, section: "recent" | "priority" | "all"): string {
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

// ── opencode 플러그인 (IO 래퍼 + 직접편집 가드) ──────────────────────────

async function load(file: string): Promise<string> {
  // 이 repo는 notepad.md가 반드시 존재한다. 없으면 엉뚱한 위치에 새로 만들지 않고 명확히 실패시킨다.
  return await readFile(file, "utf8")
}

export const NotepadPlugin: Plugin = async ({ directory }) => {
  const file = notepadPath(directory)

  return {
    tool: {
      notepad_read: tool({
        description:
          ".omc/notepad.md를 읽는다. section: recent(최상단 최근 항목 2개, 기본) | priority(하단 Priority Context 섹션) | all(전체). 이 repo는 날짜별 prepend + 하단 Priority Context 구조다.",
        args: { section: tool.schema.string() },
        async execute(args) {
          const raw = ((args.section as string) ?? "recent").toLowerCase()
          const section = raw.startsWith("pri") ? "priority" : raw.startsWith("all") ? "all" : "recent"
          return readSection(await load(file), section)
        },
      }),

      notepad_write_session: tool({
        description:
          ".omc/notepad.md 최상단(헤더 바로 아래, 첫 항목 앞)에 세션 서술 항목을 prepend한다. 헤딩은 `## <오늘 날짜> — <title>`로 자동 생성된다. content는 본문(배경 한 줄·무엇을 했는지·다음 착수 후보). 나머지 파일 내용은 절대 건드리지 않는다.",
        args: {
          title: tool.schema.string(),
          content: tool.schema.string(),
        },
        async execute(args) {
          const title = (args.title as string).trim()
          const content = (args.content as string).trim()
          if (!title || !content) throw new Error("title과 content 둘 다 필요")
          const stamp = dateStamp()
          await writeFile(file, prependSession(await load(file), title, content, stamp), "utf8")
          return `세션 항목 prepend 완료 (## ${stamp} — ${title})`
        },
      }),

      notepad_write_priority: tool({
        description:
          ".omc/notepad.md의 `## Priority Context` 섹션 본문을 교체한다(그 섹션만 치환, 나머지는 보존). 이 repo의 Priority Context는 길고 자주 바뀌지 않으므로 500자 제약이 없다 — 교체할 전체 본문을 넘긴다.",
        args: { content: tool.schema.string() },
        async execute(args) {
          const content = (args.content as string).trim()
          if (!content) throw new Error("content가 비어 있음")
          await writeFile(file, replacePriority(await load(file), content), "utf8")
          return `Priority Context 교체 완료 (${content.length}자)`
        },
      }),
    },

    "tool.execute.before": async (input, output) => {
      const t = input.tool
      if (!(t === "edit" || t === "write" || t === "apply_patch")) return
      const args = output?.args ?? {}
      const fp = (args.filePath ?? args.path ?? "") as string
      if (fp.replace(/\\/g, "/").endsWith(".omc/notepad.md")) {
        throw new Error(
          "notepad.md 직접 편집 금지(opencode 세션) — notepad_read / notepad_write_session / notepad_write_priority 툴을 사용할 것. " +
            "이 repo는 날짜별 prepend + 하단 Priority Context 구조라 직접 편집은 아카이브를 깨뜨리기 쉽다.",
        )
      }
    },
  }
}

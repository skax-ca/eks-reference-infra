import { type Plugin, tool } from "@opencode-ai/plugin"
import { readFile, writeFile } from "node:fs/promises"
import { join } from "node:path"
import { readSection, prependSession, replacePriority, type Section } from "../../.mcp/notepad-core"

// 순수 파싱/치환 로직은 ../../.mcp/notepad-core.ts에 있다 — Claude Code용 MCP 서버
// (.mcp/notepad-server.ts)와 공유한다. 이 파일은 opencode 플러그인 배선(IO + 직접편집
// 가드)만 담당한다. 로직 자체(무손실 prepend/치환 근거)는 notepad-core.ts 헤더 주석 참조.

const notepadPath = (directory: string) => join(directory, ".omc", "notepad.md")

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
          const section = (raw.startsWith("pri") ? "priority" : raw.startsWith("all") ? "all" : "recent") as Section
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
          await writeFile(file, prependSession(await load(file), title, content), "utf8")
          return `세션 항목 prepend 완료 (## ${title})`
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

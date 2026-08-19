// Claude Code용 이 repo 전용 notepad MCP 서버.
//
// 왜 필요한가 — OMC(oh-my-claudecode) 플러그인이 제공하는 mcp__t__notepad_* 툴은
// `workingDirectory`를 받지만 실제로는 "세션이 시작된 trusted git worktree 밖이면 거부하고
// trustedRoot로 되돌린다"는 의도된 보안 경계를 갖는다(OMC dist/lib/worktree-paths.js
// validateWorkingDirectory — trustedRoot = getGitTopLevel(process.cwd()), process.cwd()는
// MCP 서버 프로세스가 스폰될 때(Claude Code 세션 시작 시점)의 프로젝트 루트로 고정된다).
// 그래서 iac-module-library를 프로젝트 루트로 시작한 세션에서는 이 repo(iac-reference-infra)
// 대상으로 아무리 workingDirectory를 넘겨도 절대 쓸 수 없다 — 버그가 아니라 설계다.
// ⇒ 이 repo를 Claude Code 프로젝트 루트로 열었을 때만 로드되는, 이 repo 전용 서버가 필요하다.
//
// 로직은 .mcp/notepad-core.ts를 그대로 쓴다(opencode 플러그인과 공유, 중복 없음) — 이 파일은
// MCP 프로토콜 배선(stdio transport + 3툴 등록)과 파일 IO만 담당한다.
//
// 패턴 출처: 공식 MCP TypeScript 퀵스타트(https://modelcontextprotocol.io/quickstart/server,
// 2026-08-19 WebFetch로 확인) — McpServer + StdioServerTransport + server.registerTool().
// OMC 자체 서버(bridge/mcp-server.cjs)는 구 패키지 @modelcontextprotocol/sdk 를 쓰지만, 이
// 서버는 공식 문서가 현재 가리키는 @modelcontextprotocol/server 를 쓴다(최신 문서 기준).

import { McpServer } from "@modelcontextprotocol/server"
import { StdioServerTransport } from "@modelcontextprotocol/server/stdio"
import { z } from "zod"
import { readFile, writeFile } from "node:fs/promises"
import { join } from "node:path"
import { readSection, prependSession, replacePriority, type Section } from "./notepad-core"

// Claude Code가 스폰 시 CLAUDE_PROJECT_DIR을 프로젝트 루트로 넣어 준다(공식 문서 확인:
// "Claude Code sets CLAUDE_PROJECT_DIR in the spawned server's environment to the project
// root"). .mcp.json 등록 시 ${CLAUDE_PROJECT_DIR:-.}로도 인자에 넘기지만, 여기서도 한 번 더
// env로 직접 읽어 스크립트 자신의 위치에 기대지 않는다(다른 경로에서 실행해도 안전).
const projectDir = process.env.CLAUDE_PROJECT_DIR || process.cwd()
const notepadFile = join(projectDir, ".omc", "notepad.md")

async function load(): Promise<string> {
  return await readFile(notepadFile, "utf8")
}

const server = new McpServer({ name: "iac-reference-infra-notepad", version: "1.0.0" })

server.registerTool(
  "notepad_read",
  {
    description:
      ".omc/notepad.md를 읽는다. section: recent(최상단 최근 항목 2개, 기본) | priority(하단 Priority Context 섹션) | all(전체). 이 repo는 날짜별 prepend + 하단 Priority Context 구조다(iac-module-library의 3단 구조와 다르다).",
    inputSchema: z.object({
      section: z.enum(["recent", "priority", "all"]).optional().describe("읽을 섹션. 기본값 recent"),
    }),
  },
  async ({ section }) => {
    const text = await load()
    return { content: [{ type: "text", text: readSection(text, (section ?? "recent") as Section) }] }
  },
)

server.registerTool(
  "notepad_write_session",
  {
    description:
      ".omc/notepad.md 최상단(헤더 바로 아래, 첫 항목 앞)에 세션 서술 항목을 prepend한다. 헤딩은 `## <오늘 날짜> — <title>`로 자동 생성된다. content는 본문(배경 한 줄·무엇을 했는지·다음 착수 후보). 나머지 파일 내용은 절대 건드리지 않는다(재조립 없음).",
    inputSchema: z.object({
      title: z.string().describe("헤딩 제목(날짜는 자동으로 붙는다)"),
      content: z.string().describe("항목 본문"),
    }),
  },
  async ({ title, content }) => {
    const t = title.trim()
    const c = content.trim()
    if (!t || !c) {
      return { content: [{ type: "text", text: "오류: title과 content 둘 다 필요" }], isError: true }
    }
    const text = await load()
    await writeFile(notepadFile, prependSession(text, t, c), "utf8")
    return { content: [{ type: "text", text: `세션 항목 prepend 완료 (## ${t})` }] }
  },
)

server.registerTool(
  "notepad_write_priority",
  {
    description:
      ".omc/notepad.md의 `## Priority Context` 섹션 본문을 교체한다(그 섹션만 치환, 나머지는 보존). 이 repo의 Priority Context는 길고 자주 바뀌지 않으므로 500자 제약이 없다 — 교체할 전체 본문을 넘긴다.",
    inputSchema: z.object({
      content: z.string().describe("Priority Context를 교체할 전체 본문"),
    }),
  },
  async ({ content }) => {
    const c = content.trim()
    if (!c) {
      return { content: [{ type: "text", text: "오류: content가 비어 있음" }], isError: true }
    }
    const text = await load()
    await writeFile(notepadFile, replacePriority(text, c), "utf8")
    return { content: [{ type: "text", text: `Priority Context 교체 완료 (${c.length}자)` }] }
  },
)

async function main() {
  const transport = new StdioServerTransport()
  await server.connect(transport)
  console.error("iac-reference-infra notepad MCP server running on stdio")
}

main().catch((error) => {
  console.error("Fatal error in main():", error)
  process.exit(1)
})

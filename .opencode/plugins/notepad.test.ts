import { test, expect } from "bun:test"
import { readFileSync } from "node:fs"
import { join } from "node:path"
import {
  HEADER,
  PRIORITY_HEADING,
  dateStamp,
  topHeadingOffsets,
  readSection,
  prependSession,
  replacePriority,
} from "./notepad"

// 실제 notepad.md를 fixture로 사용한다 — 이 repo의 진짜 구조(날짜 prepend + 중간 Priority
// Context + 하단 아카이브 + 중복 항목)에 대해 무손실을 검증하는 게 이 테스트의 존재 이유다.
const NOTEPAD = readFileSync(join(import.meta.dir, "..", "..", ".omc", "notepad.md"), "utf8")

test("fixture: 실제 notepad는 헤더로 시작하고 Priority Context 섹션을 가진다", () => {
  expect(NOTEPAD.startsWith(HEADER)).toBe(true)
  expect(NOTEPAD.includes(`\n${PRIORITY_HEADING}\n`)).toBe(true)
})

test("topHeadingOffsets: 오프셋이 실제 문자열 위치를 정확히 가리킨다", () => {
  const hs = topHeadingOffsets(NOTEPAD)
  expect(hs.length).toBeGreaterThan(10)
  for (const h of hs) {
    // 각 오프셋 지점이 실제로 그 헤딩 라인의 시작이어야 한다.
    expect(NOTEPAD.slice(h.start, h.start + 3)).toBe("## ")
    expect(NOTEPAD.slice(h.start).split("\n")[0]).toBe(`## ${h.title}`)
  }
  // 첫 항목은 최신 날짜 항목, Priority Context는 중간에 있다(하단 아님).
  expect(hs[0].title.startsWith("2026-08-19")).toBe(true)
  const pIdx = hs.findIndex((h) => `## ${h.title}` === PRIORITY_HEADING)
  expect(pIdx).toBeGreaterThan(0)
  expect(pIdx).toBeLessThan(hs.length - 1) // Priority 아래에도 항목이 더 있다(아카이브)
})

test("readSection(priority): Priority Context 섹션만 정확히 잘라낸다", () => {
  const out = readSection(NOTEPAD, "priority")
  expect(out.startsWith(PRIORITY_HEADING)).toBe(true)
  // 다음 최상위 항목(Priority 바로 아래)이 새어들어오면 안 된다.
  const hs = topHeadingOffsets(NOTEPAD)
  const pIdx = hs.findIndex((h) => `## ${h.title}` === PRIORITY_HEADING)
  const nextTitle = hs[pIdx + 1].title
  expect(out.includes(`## ${nextTitle}`)).toBe(false)
  // Priority 본문의 알려진 표식은 들어와야 한다.
  expect(out.includes("레퍼런스 소비 repo")).toBe(true)
})

test("readSection(recent): 최상단 최근 2개 항목만, Priority Context는 미포함", () => {
  const out = readSection(NOTEPAD, "recent")
  const hs = topHeadingOffsets(NOTEPAD)
  expect(out.startsWith(`## ${hs[0].title}`)).toBe(true)
  expect(out.includes(`## ${hs[2].title}`)).toBe(false) // 3번째 항목은 없어야
  expect(out.includes(PRIORITY_HEADING)).toBe(false)
})

test("prependSession: 무손실 — 원본 모든 라인이 결과에 보존된다", () => {
  const out = prependSession(NOTEPAD, "테스트 세션", "본문 한 줄.", "2026-08-19")
  // 원본의 헤더 이후 전체 본문이 결과에 그대로 substring으로 남아야 한다.
  const afterHeader = NOTEPAD.slice(HEADER.length)
  expect(out.includes(afterHeader)).toBe(true)
  // 라인 수 = 원본 + 삽입 블록(헤딩 1 + 빈줄 1 + 본문 1 + 빈줄 2 = 4~5줄)
  const added = out.split("\n").length - NOTEPAD.split("\n").length
  expect(added).toBeGreaterThanOrEqual(4)
  expect(added).toBeLessThanOrEqual(5)
})

test("prependSession: 새 항목이 헤더와 기존 첫 항목 사이에 정확히 놓인다", () => {
  const out = prependSession(NOTEPAD, "테스트 세션", "본문 한 줄.", "2026-08-19")
  const hs = topHeadingOffsets(out)
  expect(hs[0].title).toBe("2026-08-19 — 테스트 세션")
  // 두 번째 항목은 원본의 원래 첫 항목이어야 한다(밀려남).
  expect(hs[1].title).toBe(topHeadingOffsets(NOTEPAD)[0].title)
  // 헤더는 여전히 파일 맨 앞.
  expect(out.startsWith(HEADER)).toBe(true)
})

test("replacePriority: Priority만 교체, 위(최근)·아래(아카이브) 항목 전부 보존", () => {
  const marker = "NEW-PRIORITY-BODY-XYZ"
  const out = replacePriority(NOTEPAD, marker)
  expect(out.includes(marker)).toBe(true)
  // 구 Priority 본문 표식은 사라져야
  expect(out.includes("레퍼런스 소비 repo")).toBe(false)
  const hsOrig = topHeadingOffsets(NOTEPAD)
  const hsNew = topHeadingOffsets(out)
  // 최상위 헤딩 개수는 동일(섹션 소실 없음)
  expect(hsNew.length).toBe(hsOrig.length)
  // Priority 위 첫 항목과 맨 아래 마지막 항목이 그대로 존재
  expect(out.includes(`## ${hsOrig[0].title}`)).toBe(true)
  expect(out.includes(`## ${hsOrig[hsOrig.length - 1].title}`)).toBe(true)
})

test("엣지: 항목 없는 최소 노트에도 안전하게 prepend", () => {
  const minimal = `${HEADER}\n\n${PRIORITY_HEADING}\n\n포인터.\n`
  const out = prependSession(minimal, "첫 항목", "본문.", "2026-08-19")
  expect(out.startsWith(HEADER)).toBe(true)
  expect(out.includes("## 2026-08-19 — 첫 항목")).toBe(true)
  expect(out.includes(PRIORITY_HEADING)).toBe(true) // Priority 보존
})

test("dateStamp: YYYY-MM-DD 형식", () => {
  expect(dateStamp(new Date(2026, 7, 19))).toBe("2026-08-19")
})

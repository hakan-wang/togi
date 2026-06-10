import { test, expect, beforeAll } from "vitest";
import Database from "better-sqlite3";
import { openReadOnly } from "../src/db.js";
import { makeReadTools } from "../src/tools/readTools.js";

const path = `/tmp/bogi-readtools-${process.pid}.sqlite`;

beforeAll(() => {
  const db = new Database(path);
  db.exec(`
    CREATE TABLE activity_segments (id TEXT PRIMARY KEY, start_at TEXT, end_at TEXT, minutes REAL,
      planned_block_id TEXT, category TEXT, sub_category TEXT, sub_sub TEXT, on_task INTEGER,
      confidence REAL, judged_at TEXT);
    CREATE TABLE planned_blocks (id TEXT PRIMARY KEY, source TEXT, external_event_id TEXT, title TEXT,
      start_at TEXT, end_at TEXT, category TEXT, goal_id TEXT, status TEXT, created_by_bogi INTEGER, updated_at TEXT);
    CREATE TABLE goals (id TEXT PRIMARY KEY, title TEXT, period TEXT, target TEXT, created_at TEXT);
    CREATE VIRTUAL TABLE segment_fts USING fts5(segment_id UNINDEXED, description);
    INSERT INTO activity_segments VALUES
      ('s1','2026-06-01T09:00:00Z','2026-06-01T09:30:00Z',30,NULL,'Work','Coding','Editing video pipeline',1,0.9,'2026-06-01T09:30:00Z'),
      ('s2','2026-06-01T10:00:00Z','2026-06-01T10:20:00Z',20,NULL,'Distraction','Social','Scrolling X',0,0.8,'2026-06-01T10:20:00Z'),
      ('s3','2026-06-02T09:00:00Z','2026-06-02T09:40:00Z',40,NULL,'Work','Coding','Editing video pipeline',1,0.9,'2026-06-02T09:40:00Z');
    INSERT INTO segment_fts VALUES ('s1','Editing video pipeline'),('s2','Scrolling X'),('s3','Editing video pipeline');
    INSERT INTO goals VALUES ('g1','Ship Bogi','quarter','beta by July','2026-05-01T00:00:00Z');
  `);
  db.close();
});

test("search_activity filters by keyword + time range", async () => {
  const tools = makeReadTools(() => openReadOnly(path));
  const search = tools.find((t) => t.name === "search_activity")!;
  const out = JSON.parse(await search.invoke({ keywords: "video", start: "2026-06-01T00:00:00Z", end: "2026-06-01T23:59:59Z" }));
  expect(out.results.length).toBe(1);
  expect(out.results[0].description).toContain("video pipeline");
});

test("summarize_range aggregates on/off task + categories", async () => {
  const tools = makeReadTools(() => openReadOnly(path));
  const summarize = tools.find((t) => t.name === "summarize_range")!;
  const out = JSON.parse(await summarize.invoke({ start: "2026-06-01T00:00:00Z", end: "2026-06-01T23:59:59Z" }));
  expect(out.totalMinutes).toBe(50);
  expect(out.onTaskMinutes).toBe(30);
  expect(out.topCategories[0].category).toBe("Work");
});

test("date-only bounds cover the whole day (summarize_range)", async () => {
  const tools = makeReadTools(() => openReadOnly(path));
  const summarize = tools.find((t) => t.name === "summarize_range")!;
  // Bare dates, no time component — must still capture same-day datetime rows.
  const out = JSON.parse(await summarize.invoke({ start: "2026-06-01", end: "2026-06-01" }));
  expect(out.totalMinutes).toBe(50);
  expect(out.onTaskMinutes).toBe(30);
});

test("list_days returns per-day totals", async () => {
  const tools = makeReadTools(() => openReadOnly(path));
  const listDays = tools.find((t) => t.name === "list_days")!;
  const out = JSON.parse(await listDays.invoke({ start: "2026-06-01T00:00:00Z", end: "2026-06-02T23:59:59Z" }));
  expect(out.days.length).toBe(2);
  expect(out.days.find((d: any) => d.date === "2026-06-02").onTaskMinutes).toBe(40);
});

test("list_goals returns active goals", async () => {
  const tools = makeReadTools(() => openReadOnly(path));
  const listGoals = tools.find((t) => t.name === "list_goals")!;
  const out = JSON.parse(await listGoals.invoke({}));
  expect(out.goals[0].title).toBe("Ship Bogi");
});

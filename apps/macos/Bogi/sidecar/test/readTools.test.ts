import { test, expect, beforeAll } from "vitest";
import Database from "better-sqlite3";
import { openReadOnly } from "../src/db.js";
import { makeReadTools } from "../src/tools/readTools.js";

const path = `/tmp/bogi-readtools-${process.pid}.sqlite`;

beforeAll(() => {
  const db = new Database(path);
  db.exec(`
    CREATE TABLE activity_segments (id TEXT PRIMARY KEY, start_at TEXT, end_at TEXT, minutes REAL,
      planned_block_id TEXT, cat TEXT, sub TEXT, title TEXT, desc TEXT, on_task INTEGER,
      confidence REAL, judged_at TEXT);
    CREATE TABLE planned_blocks (id TEXT PRIMARY KEY, source TEXT, external_event_id TEXT, title TEXT,
      start_at TEXT, end_at TEXT, cat TEXT, goal_id TEXT, status TEXT, created_by_bogi INTEGER, updated_at TEXT);
    CREATE TABLE goals (id TEXT PRIMARY KEY, title TEXT, period TEXT, target TEXT, created_at TEXT);
    CREATE TABLE activity_observations (id TEXT PRIMARY KEY, captured_at DATETIME NOT NULL,
      active_app TEXT, active_app_bundle_id TEXT, active_window_title TEXT, text TEXT,
      content_hash TEXT, capture_method TEXT NOT NULL DEFAULT 'ax',
      excluded BOOLEAN NOT NULL DEFAULT 0, focused BOOLEAN NOT NULL DEFAULT 1);
    CREATE VIRTUAL TABLE segment_fts USING fts5(segment_id UNINDEXED, description);
    CREATE TABLE category_registry (id TEXT PRIMARY KEY, name TEXT, color TEXT, description TEXT, sort_order INTEGER, created_at TEXT, updated_at TEXT);
    CREATE TABLE user_events (id TEXT PRIMARY KEY, title TEXT, desc TEXT, cat TEXT, sub TEXT, start_at TEXT, end_at TEXT, created_at TEXT);
    CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT);
    INSERT INTO activity_segments VALUES
      ('s1','2026-06-01T09:00:00Z','2026-06-01T09:30:00Z',30,NULL,'Work','Coding','Editing video pipeline',NULL,1,0.9,'2026-06-01T09:30:00Z'),
      ('s2','2026-06-01T10:00:00Z','2026-06-01T10:20:00Z',20,NULL,'Distraction','Social','Scrolling X',NULL,0,0.8,'2026-06-01T10:20:00Z'),
      ('s3','2026-06-02T09:00:00Z','2026-06-02T09:40:00Z',40,NULL,'Work','Coding','Editing video pipeline',NULL,1,0.9,'2026-06-02T09:40:00Z'),
      -- Real GRDB rows are stored space-separated with no 'Z' (see live DB), unlike the ISO
      -- literals above. s4 mirrors that format so same-day range filters are tested honestly.
      ('s4','2026-06-05 09:00:00.000','2026-06-05 09:25:00.000',25,NULL,'Work','Coding','Refactoring readTools',NULL,1,0.9,'2026-06-05 09:25:00.000');
    INSERT INTO segment_fts VALUES
      ('s1','Editing video pipeline'),('s2','Scrolling X'),('s3','Editing video pipeline'),
      ('s4','Refactoring readTools');
    INSERT INTO goals VALUES ('g1','Ship Bogi','quarter','beta by July','2026-05-01T00:00:00Z');
    -- 2026-06-06 has NO segments, only raw observations (space-format), to exercise the
    -- raw fallback: 4 observations in cmux, 1 in Safari.
    INSERT INTO activity_observations (id, captured_at, active_app, active_window_title, text, focused) VALUES
      ('o1','2026-06-06 14:00:00.000','cmux','editor','writing the fallback query',1),
      ('o2','2026-06-06 14:00:06.000','cmux','editor','writing the fallback query',1),
      ('o3','2026-06-06 14:00:12.000','cmux','editor','still in the editor',1),
      ('o4','2026-06-06 14:01:00.000','cmux','terminal','running vitest',1),
      ('o5','2026-06-06 14:05:00.000','Safari','Hacker News','reading about sqlite datetime',1);
    INSERT INTO category_registry VALUES ('deepwork','Deep work','#2E5BFF','focus',0,'','' ),('scroll','Scroll','#EF4444','feeds',1,'','');
    INSERT INTO user_events (id,title,cat,start_at,end_at,created_at) VALUES ('ev1','Gym','health','2026-06-06 18:00:00.000','2026-06-06 19:00:00.000','2026-06-06 08:00:00.000');
    INSERT INTO settings (key, value) VALUES ('user_display_name','Erik'),('north_star','Ship Togi'),('behaviour_profile','- loses focus after 35m');
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

// --- timestamp-format compatibility: real rows are space-separated, bounds arrive as ISO 'T...Z' ---

test("summarize_range matches space-separated datetimes via same-day bounds", async () => {
  const tools = makeReadTools(() => openReadOnly(path));
  const summarize = tools.find((t) => t.name === "summarize_range")!;
  const out = JSON.parse(await summarize.invoke({ start: "2026-06-05", end: "2026-06-05" }));
  expect(out.totalMinutes).toBe(25);
  expect(out.onTaskMinutes).toBe(25);
});

test("search_activity matches space-separated datetimes via same-day bounds", async () => {
  const tools = makeReadTools(() => openReadOnly(path));
  const search = tools.find((t) => t.name === "search_activity")!;
  const out = JSON.parse(await search.invoke({ keywords: "readTools", start: "2026-06-05", end: "2026-06-05" }));
  expect(out.results.length).toBe(1);
  expect(out.results[0].description).toContain("Refactoring");
});

test("list_days matches space-separated datetimes", async () => {
  const tools = makeReadTools(() => openReadOnly(path));
  const listDays = tools.find((t) => t.name === "list_days")!;
  const out = JSON.parse(await listDays.invoke({ start: "2026-06-05", end: "2026-06-05" }));
  expect(out.days.find((d: any) => d.date === "2026-06-05")?.onTaskMinutes).toBe(25);
});

// --- raw-observation fallback: a range with no judged segments still surfaces raw activity ---

test("summarize_range falls back to raw observations when no segments", async () => {
  const tools = makeReadTools(() => openReadOnly(path));
  const summarize = tools.find((t) => t.name === "summarize_range")!;
  const out = JSON.parse(await summarize.invoke({ start: "2026-06-06", end: "2026-06-06" }));
  // No segments that day → estimate from the 5 raw observations (6s each = 0.1 min).
  expect(out.source).toBe("observations");
  expect(out.observationCount).toBe(5);
  expect(out.topCategories[0].category).toBe("cmux"); // 4 obs in cmux dominates
});

test("search_activity falls back to raw observations when no segments match", async () => {
  const tools = makeReadTools(() => openReadOnly(path));
  const search = tools.find((t) => t.name === "search_activity")!;
  const out = JSON.parse(await search.invoke({ keywords: "fallback", start: "2026-06-06", end: "2026-06-06" }));
  expect(out.source).toBe("observations");
  expect(out.results.length).toBeGreaterThan(0);
  expect(out.results[0].description).toContain("fallback query");
});

// --- Task 8: events in summarize_range ---

test("summarize_range includes user events in range", async () => {
  const tools = makeReadTools(() => openReadOnly(path));
  const out = JSON.parse(await tools.find((t) => t.name === "summarize_range")!.invoke({ start: "2026-06-06", end: "2026-06-06" }));
  expect(out.events.map((e: any) => e.title)).toContain("Gym");
});

// --- Task 7: list_categories, read_behaviour, list_events ---

test("list_categories returns the registry ordered", async () => {
  const tools = makeReadTools(() => openReadOnly(path));
  const out = JSON.parse(await tools.find((t) => t.name === "list_categories")!.invoke({}));
  expect(out.categories.map((c: any) => c.id)).toEqual(["deepwork", "scroll"]);
  expect(out.categories[0].color).toBe("#2E5BFF");
});

test("read_behaviour returns identity + learned behaviour", async () => {
  const tools = makeReadTools(() => openReadOnly(path));
  const out = JSON.parse(await tools.find((t) => t.name === "read_behaviour")!.invoke({}));
  expect(out.name).toBe("Erik");
  expect(out.northStar).toBe("Ship Togi");
  expect(out.behaviour).toContain("35m");
});

test("list_events filters by range", async () => {
  const tools = makeReadTools(() => openReadOnly(path));
  const out = JSON.parse(await tools.find((t) => t.name === "list_events")!.invoke({ start: "2026-06-06", end: "2026-06-06" }));
  expect(out.events.length).toBe(1);
  expect(out.events[0].title).toBe("Gym");
});

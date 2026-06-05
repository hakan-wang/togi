import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

describe("screen frame batch migration", () => {
  it("stores frame metadata without requiring raw frame content", () => {
    const migration = readFileSync("supabase/migrations/0001_initial_bogi_schema.sql", "utf8");

    expect(migration).toContain("create table public.screen_frame_batches");
    expect(migration).toContain("frame_hash text not null");
    expect(migration).toContain("raw_frame_stored_until timestamptz");
  });
});

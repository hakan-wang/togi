import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

describe("supabase migrations", () => {
  it("enforces confirmed reality logs at database boundary", () => {
    const migration = readFileSync("supabase/migrations/202606050001_initial_core.sql", "utf8");

    expect(migration).toContain("confirmed_by_user boolean not null default true");
    expect(migration).toContain("check (confirmed_by_user = true)");
  });
});

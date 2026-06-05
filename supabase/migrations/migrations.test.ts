import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

describe("supabase migrations", () => {
  const readInitialMigration = () => readFileSync("supabase/migrations/202606050001_initial_core.sql", "utf8");

  it("enforces confirmed reality logs at database boundary", () => {
    const migration = readInitialMigration();

    expect(migration).toContain("confirmed_by_user boolean not null default true");
    expect(migration).toContain("check (confirmed_by_user = true)");
  });

  it("enforces checkable planned blocks at database boundary", () => {
    const migration = readInitialMigration();

    expect(migration).toContain("check (jsonb_array_length(success_criteria) > 0)");
    expect(migration).toContain("check (lower(trim(intention_text)) not in ('be productive', 'work', 'focus', 'catch up', 'do stuff'))");
  });
});

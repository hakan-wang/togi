import { getTableName } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import { dailySummaries, embeddings, plannedBlocks, realityLogs, users } from "../src/db/schema";

describe("database schema", () => {
  it("defines core cloud data-bank tables", () => {
    expect(getTableName(users)).toBe("users");
    expect(getTableName(plannedBlocks)).toBe("planned_blocks");
    expect(getTableName(realityLogs)).toBe("reality_logs");
    expect(getTableName(dailySummaries)).toBe("daily_summaries");
    expect(getTableName(embeddings)).toBe("embeddings");
  });
});

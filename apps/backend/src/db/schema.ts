import { index, pgTable, text, timestamp, uuid, vector } from "drizzle-orm/pg-core";

export const users = pgTable("users", {
  id: uuid("id").primaryKey(),
  email: text("email").notNull(),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull()
});

export const plannedBlocks = pgTable("planned_blocks", {
  id: uuid("id").primaryKey(),
  userId: uuid("user_id").notNull().references(() => users.id),
  title: text("title").notNull(),
  startAt: timestamp("start_at", { withTimezone: true }).notNull(),
  endAt: timestamp("end_at", { withTimezone: true }).notNull(),
  source: text("source").notNull(),
  externalEventId: text("external_event_id"),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull()
});

export const realityLogs = pgTable("reality_logs", {
  id: uuid("id").primaryKey(),
  userId: uuid("user_id").notNull().references(() => users.id),
  plannedBlockId: uuid("planned_block_id").references(() => plannedBlocks.id),
  userText: text("user_text").notNull(),
  generatedSummary: text("generated_summary"),
  startAt: timestamp("start_at", { withTimezone: true }).notNull(),
  endAt: timestamp("end_at", { withTimezone: true }).notNull(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull()
});

export const dailySummaries = pgTable("daily_summaries", {
  id: uuid("id").primaryKey(),
  userId: uuid("user_id").notNull().references(() => users.id),
  day: text("day").notNull(),
  summary: text("summary").notNull(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull()
});

export const embeddings = pgTable(
  "embeddings",
  {
    id: uuid("id").primaryKey(),
    userId: uuid("user_id").notNull().references(() => users.id),
    sourceType: text("source_type").notNull(),
    sourceId: uuid("source_id").notNull(),
    embedding: vector("embedding", { dimensions: 1536 }).notNull(),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull()
  },
  (table) => ({
    embeddingIndex: index("embeddings_vector_idx").using("hnsw", table.embedding.op("vector_cosine_ops"))
  })
);

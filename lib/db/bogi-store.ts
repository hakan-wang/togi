import type { PlannerOutput, RealityLogInput } from "@/lib/zod/contracts";

export type BogiStoreClient = {
  // Supabase's generated client type is deeply generic; this store only needs
  // the small query-builder surface below.
  from(table: string): any;
};

export type ExportedUserData = {
  plannedBlocks: unknown[];
  realityLogs: unknown[];
  screenObservationSummaries: unknown[];
  dailySummaries: unknown[];
  weeklySummaries: unknown[];
  monthlySummaries: unknown[];
  userPatterns: unknown[];
};

export type SummaryScope = "day" | "week" | "month";

const exportTables: Array<[keyof ExportedUserData, string]> = [
  ["plannedBlocks", "planned_blocks"],
  ["realityLogs", "reality_logs"],
  ["screenObservationSummaries", "screen_observation_summaries"],
  ["dailySummaries", "daily_summaries"],
  ["weeklySummaries", "weekly_summaries"],
  ["monthlySummaries", "monthly_summaries"],
  ["userPatterns", "user_patterns"]
];

async function readUserRows(client: BogiStoreClient, table: string, userId: string) {
  const result = await client.from(table).select("*").eq("user_id", userId);
  if (result.error) throw new Error(result.error.message);
  return result.data ?? [];
}

export async function exportUserData(client: BogiStoreClient, userId: string): Promise<ExportedUserData> {
  const entries = await Promise.all(
    exportTables.map(async ([key, table]) => [key, await readUserRows(client, table, userId)] as const)
  );
  return Object.fromEntries(entries) as ExportedUserData;
}

export async function deleteUserData(client: BogiStoreClient, userId: string) {
  const result = await client.from("users").delete().eq("id", userId);
  if (result.error) throw new Error(result.error.message);
}

export function mapRealityLogInsert(userId: string, log: RealityLogInput) {
  return {
    planned_block_id: log.plannedBlockId,
    user_id: userId,
    actual_summary: log.actualSummary,
    completion_score: log.completionScore,
    deviation_reason: log.deviationReason,
    actual_categories_json: log.actualCategories,
    confirmed_by_user: log.confirmedByUser,
    source: "user_confirmed"
  };
}

type PlannedBlock = PlannerOutput["blocks"][number];

export function mapPlannedBlockInsert(userId: string, block: PlannedBlock, calendarEventId: string | null = null) {
  return {
    user_id: userId,
    calendar_event_id: calendarEventId,
    title: block.title,
    start_time: block.start,
    end_time: block.end,
    intention_text: block.title,
    success_criteria: block.successCriteria,
    category: block.category,
    created_by: "planner_agent"
  };
}

export async function savePlannedBlocks(client: BogiStoreClient, userId: string, blocks: PlannedBlock[]) {
  const saved = [];
  for (const block of blocks) {
    const result = await client
      .from("planned_blocks")
      .insert(mapPlannedBlockInsert(userId, block))
      .select("*")
      .single();
    if (result.error) throw new Error(result.error.message);
    saved.push(result.data);
  }
  return saved;
}

export async function saveRealityLog(client: BogiStoreClient, userId: string, log: RealityLogInput) {
  const result = await client
    .from("reality_logs")
    .insert(mapRealityLogInsert(userId, log))
    .select("*")
    .single();
  if (result.error) throw new Error(result.error.message);
  return result.data;
}

export function mapCalendarConnectionInsert(userId: string, input: {
  accessToken: string;
  refreshToken: string;
  syncToken?: string | null;
  channelId?: string | null;
  resourceId?: string | null;
  expiresAt?: string | null;
}) {
  const insert: Record<string, string | null> = {
    user_id: userId,
    provider: "google",
    access_token: input.accessToken,
    refresh_token: input.refreshToken
  };
  if (input.syncToken !== undefined) insert.sync_token = input.syncToken;
  if (input.channelId !== undefined) insert.channel_id = input.channelId;
  if (input.resourceId !== undefined) insert.resource_id = input.resourceId;
  if (input.expiresAt !== undefined) insert.expires_at = input.expiresAt;
  return insert;
}

export function mapScreenFrameBatchInsert(input: {
  userId: string;
  plannedBlockId: string;
  screenSessionId?: string | null;
  hash: string;
  capturedAt: string;
  rawFrameStoredUntil?: string | null;
}) {
  return {
    user_id: input.userId,
    planned_block_id: input.plannedBlockId,
    screen_session_id: input.screenSessionId ?? null,
    frame_hash: input.hash,
    captured_at: input.capturedAt,
    raw_frame_stored_until: input.rawFrameStoredUntil ?? null
  };
}

export async function saveScreenFrameBatch(
  client: BogiStoreClient,
  input: {
    userId: string;
    plannedBlockId: string;
    screenSessionId?: string | null;
    hash: string;
    capturedAt: string;
  }
) {
  const result = await client
    .from("screen_frame_batches")
    .insert(mapScreenFrameBatchInsert(input))
    .select("id")
    .single();
  if (result.error) throw new Error(result.error.message);
  return result.data;
}

export function getSummaryTable(scope: SummaryScope) {
  if (scope === "week") return { table: "weekly_summaries", dateColumn: "week_start" };
  if (scope === "month") return { table: "monthly_summaries", dateColumn: "month_start" };
  return { table: "daily_summaries", dateColumn: "day" };
}

export function mapStoredSummary(scope: SummaryScope, row: Record<string, unknown>) {
  return {
    scope,
    summary: String(row.summary ?? ""),
    stats: row.stats_json ?? {}
  };
}

export async function getStoredSummary(
  client: BogiStoreClient,
  input: { userId: string; scope: SummaryScope; date: string }
) {
  const { table, dateColumn } = getSummaryTable(input.scope);
  const result = await client
    .from(table)
    .select("summary, stats_json")
    .eq("user_id", input.userId)
    .eq(dateColumn, input.date)
    .single();
  if (result.error) throw new Error(result.error.message);
  return mapStoredSummary(input.scope, result.data ?? {});
}

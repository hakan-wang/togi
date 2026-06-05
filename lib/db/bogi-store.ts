import type { PlannerOutput, RealityLogInput, ScreenObservationOutput } from "@/lib/zod/contracts";

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
export type AgentRunStatus = "started" | "succeeded" | "failed";

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

export async function savePlannedBlock(
  client: BogiStoreClient,
  userId: string,
  block: PlannedBlock,
  calendarEventId: string | null = null
) {
  const result = await client
    .from("planned_blocks")
    .insert(mapPlannedBlockInsert(userId, block, calendarEventId))
    .select("*")
    .single();
  if (result.error) throw new Error(result.error.message);
  return result.data;
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

export async function saveCalendarConnection(
  client: BogiStoreClient,
  userId: string,
  input: {
    accessToken: string;
    refreshToken: string;
    syncToken?: string | null;
    channelId?: string | null;
    resourceId?: string | null;
    expiresAt?: string | null;
  }
) {
  const result = await client
    .from("calendar_connections")
    .insert(mapCalendarConnectionInsert(userId, input))
    .select("*")
    .single();
  if (result.error) throw new Error(result.error.message);
  return result.data;
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

export function mapScreenObservationSummaryInsert(input: {
  plannedBlockId: string;
  screenSessionId: string;
  timeWindowStart: string;
  timeWindowEnd: string;
  observation: ScreenObservationOutput;
  rawFramesStoredUntil?: string | null;
}) {
  const confidences = input.observation.observedActivities.map((activity) => activity.confidence);
  const confidence = confidences.length
    ? Math.round((confidences.reduce((sum, value) => sum + value, 0) / confidences.length) * 100) / 100
    : 0;

  return {
    planned_block_id: input.plannedBlockId,
    screen_session_id: input.screenSessionId,
    time_window_start: input.timeWindowStart,
    time_window_end: input.timeWindowEnd,
    observed_activities_json: input.observation.observedActivities,
    confidence,
    raw_frames_stored_until: input.rawFramesStoredUntil ?? null
  };
}

export async function saveScreenObservationSummary(
  client: BogiStoreClient,
  input: {
    plannedBlockId: string;
    screenSessionId: string;
    timeWindowStart: string;
    timeWindowEnd: string;
    observation: ScreenObservationOutput;
  }
) {
  const result = await client
    .from("screen_observation_summaries")
    .insert(mapScreenObservationSummaryInsert(input))
    .select("*")
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

export type StoredSummaryInput = {
  userId: string;
  scope: SummaryScope;
  date: string;
  summary: string;
  stats: Record<string, unknown>;
};

export function mapSummaryUpsert(input: StoredSummaryInput) {
  const { table, dateColumn } = getSummaryTable(input.scope);
  return {
    table,
    value: {
      user_id: input.userId,
      [dateColumn]: input.date,
      summary: input.summary,
      stats_json: input.stats
    },
    conflict: `user_id,${dateColumn}`
  };
}

export async function upsertStoredSummary(client: BogiStoreClient, input: StoredSummaryInput) {
  const mapped = mapSummaryUpsert(input);
  const result = await client
    .from(mapped.table)
    .upsert(mapped.value, { onConflict: mapped.conflict })
    .select("*")
    .single();
  if (result.error) throw new Error(result.error.message);
  return result.data;
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

export type UserPatternInput = {
  patternKey: string;
  evidence: Record<string, unknown>;
  recommendation: string;
};

export function mapPatternUpsert(userId: string, pattern: UserPatternInput) {
  return {
    user_id: userId,
    pattern_key: pattern.patternKey,
    evidence_json: pattern.evidence,
    recommendation: pattern.recommendation
  };
}

export async function upsertUserPattern(client: BogiStoreClient, userId: string, pattern: UserPatternInput) {
  const result = await client
    .from("user_patterns")
    .upsert(mapPatternUpsert(userId, pattern), { onConflict: "user_id,pattern_key" })
    .select("*")
    .single();
  if (result.error) throw new Error(result.error.message);
  return result.data;
}

export async function getRelevantPatterns(client: BogiStoreClient, userId: string, category: string) {
  const result = await client
    .from("user_patterns")
    .select("pattern_key, evidence_json, recommendation, updated_at")
    .eq("user_id", userId)
    .ilike("pattern_key", `${category}%`)
    .order("updated_at", { ascending: false });
  if (result.error) throw new Error(result.error.message);
  return result.data ?? [];
}

export type AgentRunInput = {
  userId: string | null;
  agentName: string;
  input: unknown;
  output: unknown;
  status: AgentRunStatus;
};

export function mapAgentRunInsert(run: AgentRunInput) {
  return {
    user_id: run.userId,
    agent_name: run.agentName,
    input_json: run.input,
    output_json: run.output,
    status: run.status
  };
}

export async function saveAgentRun(client: BogiStoreClient, run: AgentRunInput) {
  const result = await client
    .from("agent_runs")
    .insert(mapAgentRunInsert(run))
    .select("*")
    .single();
  if (result.error) throw new Error(result.error.message);
  return result.data;
}

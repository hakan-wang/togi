import type { RealityLogInput } from "@/lib/zod/contracts";

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

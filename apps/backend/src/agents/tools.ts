import { z } from "zod";

export const BogiToolNameSchema = z.enum([
  "read_calendar",
  "create_calendar_block",
  "update_calendar_block",
  "get_planned_blocks",
  "save_reality_log",
  "get_reality_logs",
  "get_user_patterns",
  "summarize_day",
  "summarize_week",
  "suggest_next_plan",
  "start_lock_in_session",
  "end_lock_in_session",
  "search_local_history",
  "export_user_data"
]);

export type BogiToolName = z.infer<typeof BogiToolNameSchema>;

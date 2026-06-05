import type { SupabaseClient } from "@supabase/supabase-js";
import { createCoachAgentService } from "@/server/services/agents/coach-agent.service";
import { createPlannerAgentService } from "@/server/services/agents/planner-agent.service";
import { createRealityLogAgentService } from "@/server/services/agents/reality-log-agent.service";
import { badRequest, notFound } from "@/server/lib/errors";
import type { AgentRun } from "@/server/schemas/agents";
import type { CreateGoalInput, Goal, UpdateGoalInput } from "@/server/schemas/goals";
import type { UserPattern } from "@/server/schemas/patterns";
import type { CreatePlannedBlockInput, PlannedBlock, UpdatePlannedBlockInput } from "@/server/schemas/planned-blocks";
import type { CreateRealityLogInput, RealityLog, UpdateRealityLogInput } from "@/server/schemas/reality-logs";
import { assertCheckablePlannedBlock } from "@/server/services/planned-blocks/planned-blocks.service";
import { assertConfirmedRealityLog } from "@/server/services/reality-logs/reality-logs.service";
import type { TogiStore } from "./store";

type EnvLike = Record<string, string | undefined>;

export const shouldUseSupabaseStore = (env: EnvLike) => Boolean(env.SUPABASE_URL && env.SUPABASE_SERVICE_ROLE_KEY);

const requireSingle = <T>(data: T | null, error: { message?: string } | null, resource: string): T => {
  if (error) throw badRequest(error.message ?? `${resource} query failed`);
  if (!data) throw notFound(resource);
  return data;
};

export const mapGoalRow = (row: Record<string, any>): Goal => ({
  id: row.id,
  userId: row.user_id,
  title: row.title,
  description: row.description,
  status: row.status,
  createdAt: row.created_at,
  updatedAt: row.updated_at
});

export const mapPlannedBlockRow = (row: Record<string, any>): PlannedBlock => ({
  id: row.id,
  userId: row.user_id,
  calendarEventId: row.calendar_event_id,
  title: row.title,
  startTime: row.start_time,
  endTime: row.end_time,
  intentionText: row.intention_text,
  successCriteria: row.success_criteria,
  category: row.category,
  status: row.status,
  createdBy: row.created_by,
  createdAt: row.created_at,
  updatedAt: row.updated_at
});

export const mapRealityLogRow = (row: Record<string, any>): RealityLog => ({
  id: row.id,
  userId: row.user_id,
  plannedBlockId: row.planned_block_id,
  actualSummary: row.actual_summary,
  completionScore: Number(row.completion_score),
  deviationReason: row.deviation_reason,
  actualCategories: row.actual_categories_json,
  confirmedByUser: row.confirmed_by_user,
  source: row.source,
  createdAt: row.created_at,
  updatedAt: row.updated_at
});

export const mapAgentRunRow = (row: Record<string, any>): AgentRun => ({
  id: row.id,
  userId: row.user_id,
  agentName: row.agent_name,
  inputJson: row.input_json,
  outputJson: row.output_json,
  status: row.status,
  error: row.error,
  model: row.model,
  startedAt: row.started_at,
  completedAt: row.completed_at
});

const mapPatternRow = (row: Record<string, any>): UserPattern => ({
  id: row.id,
  userId: row.user_id,
  patternType: row.pattern_type,
  evidenceJson: row.evidence_json,
  recommendation: row.recommendation,
  confidence: Number(row.confidence),
  createdAt: row.created_at,
  updatedAt: row.updated_at
});

const plannedBlockRow = (userId: string, input: CreatePlannedBlockInput | UpdatePlannedBlockInput) => ({
  user_id: userId,
  calendar_event_id: input.calendarEventId,
  title: input.title,
  start_time: input.startTime,
  end_time: input.endTime,
  intention_text: input.intentionText,
  success_criteria: input.successCriteria,
  category: input.category,
  created_by: input.createdBy,
  status: "status" in input ? input.status : undefined
});

const cleanRow = <T extends Record<string, unknown>>(row: T) =>
  Object.fromEntries(Object.entries(row).filter(([, value]) => value !== undefined));

export const createSupabaseServices = (client: SupabaseClient) => {
  const goals = {
    async list(userId: string): Promise<Goal[]> {
      const { data, error } = await client.from("goals").select("*").eq("user_id", userId).order("created_at");
      if (error) throw badRequest(error.message);
      return (data ?? []).map(mapGoalRow);
    },
    async create(userId: string, input: CreateGoalInput): Promise<Goal> {
      const { data, error } = await client
        .from("goals")
        .insert({ user_id: userId, title: input.title, description: input.description ?? null })
        .select("*")
        .single();
      return mapGoalRow(requireSingle(data, error, "goal"));
    },
    async update(userId: string, id: string, input: UpdateGoalInput): Promise<Goal> {
      const { data, error } = await client.from("goals").update(input).eq("id", id).eq("user_id", userId).select("*").single();
      return mapGoalRow(requireSingle(data, error, "goal"));
    }
  };

  const plannedBlocks = {
    async list(userId: string): Promise<PlannedBlock[]> {
      const { data, error } = await client.from("planned_blocks").select("*").eq("user_id", userId).order("start_time");
      if (error) throw badRequest(error.message);
      return (data ?? []).map(mapPlannedBlockRow);
    },
    async get(userId: string, id: string): Promise<PlannedBlock> {
      const { data, error } = await client.from("planned_blocks").select("*").eq("id", id).eq("user_id", userId).single();
      return mapPlannedBlockRow(requireSingle(data, error, "planned block"));
    },
    async create(userId: string, input: CreatePlannedBlockInput): Promise<PlannedBlock> {
      assertCheckablePlannedBlock(input);
      const { data, error } = await client.from("planned_blocks").insert(cleanRow(plannedBlockRow(userId, input))).select("*").single();
      return mapPlannedBlockRow(requireSingle(data, error, "planned block"));
    },
    async update(userId: string, id: string, input: UpdatePlannedBlockInput): Promise<PlannedBlock> {
      const existing = await this.get(userId, id);
      assertCheckablePlannedBlock({
        title: input.title ?? existing.title,
        intentionText: input.intentionText ?? existing.intentionText,
        successCriteria: input.successCriteria ?? existing.successCriteria
      });
      const { data, error } = await client
        .from("planned_blocks")
        .update(cleanRow(plannedBlockRow(userId, input)))
        .eq("id", id)
        .eq("user_id", userId)
        .select("*")
        .single();
      return mapPlannedBlockRow(requireSingle(data, error, "planned block"));
    },
    async delete(userId: string, id: string): Promise<void> {
      const { error } = await client.from("planned_blocks").delete().eq("id", id).eq("user_id", userId);
      if (error) throw badRequest(error.message);
    }
  };

  const realityLogs = {
    async list(userId: string): Promise<RealityLog[]> {
      const { data, error } = await client.from("reality_logs").select("*").eq("user_id", userId).order("created_at");
      if (error) throw badRequest(error.message);
      return (data ?? []).map(mapRealityLogRow);
    },
    async get(userId: string, id: string): Promise<RealityLog> {
      const { data, error } = await client.from("reality_logs").select("*").eq("id", id).eq("user_id", userId).single();
      return mapRealityLogRow(requireSingle(data, error, "reality log"));
    },
    async create(userId: string, input: CreateRealityLogInput): Promise<RealityLog> {
      assertConfirmedRealityLog(input);
      await plannedBlocks.get(userId, input.plannedBlockId);
      const { data, error } = await client
        .from("reality_logs")
        .insert({
          user_id: userId,
          planned_block_id: input.plannedBlockId,
          actual_summary: input.actualSummary,
          completion_score: input.completionScore,
          deviation_reason: input.deviationReason,
          actual_categories_json: input.actualCategories,
          confirmed_by_user: input.confirmedByUser,
          source: input.source
        })
        .select("*")
        .single();
      return mapRealityLogRow(requireSingle(data, error, "reality log"));
    },
    async update(userId: string, id: string, input: UpdateRealityLogInput): Promise<RealityLog> {
      const existing = await this.get(userId, id);
      assertConfirmedRealityLog({ confirmedByUser: input.confirmedByUser ?? existing.confirmedByUser });
      const { data, error } = await client
        .from("reality_logs")
        .update(cleanRow({
          actual_summary: input.actualSummary,
          completion_score: input.completionScore,
          deviation_reason: input.deviationReason,
          actual_categories_json: input.actualCategories,
          confirmed_by_user: input.confirmedByUser,
          source: input.source
        }))
        .eq("id", id)
        .eq("user_id", userId)
        .select("*")
        .single();
      return mapRealityLogRow(requireSingle(data, error, "reality log"));
    }
  };

  const agentRuns = {
    async list(userId: string): Promise<AgentRun[]> {
      const { data, error } = await client.from("agent_runs").select("*").eq("user_id", userId).order("started_at");
      if (error) throw badRequest(error.message);
      return (data ?? []).map(mapAgentRunRow);
    },
    async record<T>(userId: string, agentName: string, inputJson: unknown, model: string, run: () => Promise<T>): Promise<T> {
      const { data, error } = await client
        .from("agent_runs")
        .insert({ user_id: userId, agent_name: agentName, input_json: inputJson, status: "started", model })
        .select("*")
        .single();
      const started = requireSingle(data, error, "agent run");

      try {
        const output = await run();
        await client.from("agent_runs").update({ output_json: output, status: "completed", completed_at: new Date().toISOString() }).eq("id", started.id);
        return output;
      } catch (caught) {
        await client
          .from("agent_runs")
          .update({
            status: "failed",
            error: caught instanceof Error ? caught.message : "Unknown error",
            completed_at: new Date().toISOString()
          })
          .eq("id", started.id);
        throw caught;
      }
    }
  };

  const patterns = {
    async list(userId: string): Promise<UserPattern[]> {
      const { data, error } = await client.from("user_patterns").select("*").eq("user_id", userId).order("created_at");
      if (error) throw badRequest(error.message);
      return (data ?? []).map(mapPatternRow);
    }
  };

  return {
    store: { goals: [], plannedBlocks: [], realityLogs: [], agentRuns: [], userPatterns: [] },
    goals,
    plannedBlocks,
    realityLogs,
    patterns,
    agentRuns,
    plannerAgent: createPlannerAgentService(agentRuns),
    realityLogAgent: createRealityLogAgentService(agentRuns),
    coachAgent: createCoachAgentService({ listRealityLogs: realityLogs.list }, agentRuns)
  };
};

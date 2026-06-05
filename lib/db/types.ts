export type PlannedBlock = {
  id: string;
  userId: string;
  calendarEventId: string | null;
  title: string;
  startTime: string;
  endTime: string;
  intentionText: string;
  successCriteria: string;
  category: string;
  createdBy: "user" | "planner_agent";
};

export type ActualCategory = {
  category: string;
  minutes: number;
};

export type RealityLog = {
  id: string;
  plannedBlockId: string;
  userId: string;
  actualSummary: string;
  completionScore: number;
  deviationReason: string;
  actualCategories: ActualCategory[];
  confirmedByUser: boolean;
  source: "manual" | "screen_assisted" | "user_confirmed";
};

export type ObservedActivity = {
  activity: string;
  estimatedMinutes: number;
  confidence: number;
};

export type ScreenObservationSummary = {
  id: string;
  plannedBlockId: string;
  screenSessionId: string;
  timeWindowStart: string;
  timeWindowEnd: string;
  observedActivities: ObservedActivity[];
  confidence: number;
  rawFramesStoredUntil: string | null;
};

export function buildPrivacyExport(userId: string) {
  return {
    version: 1,
    userId,
    plannedBlocks: [],
    realityLogs: [],
    summaries: []
  };
}

import { task } from "@trigger.dev/sdk/v3";

export const patternUpdate = task({
  id: "pattern_update",
  run: async (payload: { userId: string }) => ({
    userId: payload.userId,
    status: "queued_for_phase_2"
  })
});

import { task } from "@trigger.dev/sdk/v3";

export const blockEndCheckin = task({
  id: "block_end_checkin",
  run: async (payload: { userId: string; plannedBlockId: string }) => ({
    userId: payload.userId,
    plannedBlockId: payload.plannedBlockId,
    action: "request_reality_log"
  })
});

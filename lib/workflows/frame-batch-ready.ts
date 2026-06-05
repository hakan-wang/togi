export const frameBatchReadyEvent = "lockin.frame_batch.ready";

export type FrameBatchReadyPayload = {
  userId: string;
  plannedBlockId: string;
  screenSessionId: string;
  frameCount: number;
};

export const frameBatchReadyEvent = "lockin.frame_batch.ready";

export type FrameBatchReadyPayload = {
  userId: string;
  plannedBlockId: string;
  screenSessionId: string;
  frameCount: number;
};

export type FrameBatchReadyDeps = {
  observeFrameBatch(payload: FrameBatchReadyPayload): Promise<unknown>;
};

export async function handleFrameBatchReady(payload: FrameBatchReadyPayload, deps: FrameBatchReadyDeps) {
  const observation = await deps.observeFrameBatch(payload);
  return {
    event: frameBatchReadyEvent,
    next: "screen_observation",
    observation
  };
}

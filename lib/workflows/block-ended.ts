export const blockEndedEvent = "calendar.block.ended";

export type BlockEndedPayload = {
  userId: string;
  plannedBlockId: string;
  endedAt: string;
};

export type BlockEndedDeps = {
  enqueueRealityConfirmation(payload: BlockEndedPayload): Promise<unknown>;
};

export async function handleBlockEnded(payload: BlockEndedPayload, deps: BlockEndedDeps) {
  const job = await deps.enqueueRealityConfirmation(payload);
  return {
    event: blockEndedEvent,
    next: "reality_confirmation",
    job
  };
}

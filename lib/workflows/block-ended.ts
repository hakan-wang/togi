export const blockEndedEvent = "calendar.block.ended";

export type BlockEndedPayload = {
  userId: string;
  plannedBlockId: string;
  endedAt: string;
};

export type FrameBatchFrame = {
  capturedAt: string;
  hash: string;
  imageBase64: string;
};

export type FrameBatchState = {
  seenHashes: Set<string>;
  frames: FrameBatchFrame[];
};

export function addFrameToBatch(state: FrameBatchState, frame: FrameBatchFrame, batchSize: number) {
  if (state.seenHashes.has(frame.hash)) {
    return { state, added: false, ready: state.frames.length >= batchSize };
  }

  const seenHashes = new Set(state.seenHashes);
  seenHashes.add(frame.hash);
  const frames = [...state.frames, frame];
  return {
    state: { seenHashes, frames },
    added: true,
    ready: frames.length >= batchSize
  };
}

export function createFrameBatchFormData(input: {
  userId?: string;
  plannedBlockId: string;
  screenSessionId?: string;
  timeWindowStart: string;
  timeWindowEnd: string;
  frames: FrameBatchFrame[];
}) {
  const latest = input.frames.at(-1);
  const form = new FormData();
  if (input.userId) form.append("userId", input.userId);
  if (input.screenSessionId) form.append("screenSessionId", input.screenSessionId);
  form.append("plannedBlockId", input.plannedBlockId);
  form.append("capturedAt", latest?.capturedAt ?? input.timeWindowEnd);
  form.append("hash", latest?.hash ?? "empty_batch");
  form.append("batchReady", "true");
  form.append("timeWindowStart", input.timeWindowStart);
  form.append("timeWindowEnd", input.timeWindowEnd);
  form.append("framesJson", JSON.stringify(input.frames.map(({ capturedAt, imageBase64 }) => ({ capturedAt, imageBase64 }))));
  return form;
}

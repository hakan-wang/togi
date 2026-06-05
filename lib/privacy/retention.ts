export type FrameRetentionPolicy = {
  storeRawFrames: boolean;
  deleteRawFramesAfterMinutes: number;
  permanentStorage: "summaries_only";
};

export function getFrameRetentionPolicy(input: { rawFramesEnabled: boolean }): FrameRetentionPolicy {
  if (!input.rawFramesEnabled) {
    return {
      storeRawFrames: false,
      deleteRawFramesAfterMinutes: 0,
      permanentStorage: "summaries_only"
    };
  }

  return {
    storeRawFrames: true,
    deleteRawFramesAfterMinutes: 60,
    permanentStorage: "summaries_only"
  };
}

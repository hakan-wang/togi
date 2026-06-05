export type CapturedFrame = {
  capturedAt: string;
  hash: string;
  blob: Blob;
};

export type FrameSampleConfig = {
  intervalMs: number;
  jpegQuality: number;
  targetWidth: number;
};

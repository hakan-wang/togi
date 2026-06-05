export function shouldSampleFrame(input: { lastSampleAt: number; now: number; intervalMs: number }) {
  return input.now - input.lastSampleAt >= input.intervalMs;
}

export function targetCanvasSize(input: { width: number; height: number; targetWidth: number }) {
  if (input.width <= input.targetWidth) return { width: input.width, height: input.height };
  const ratio = input.targetWidth / input.width;
  return { width: input.targetWidth, height: Math.round(input.height * ratio) };
}

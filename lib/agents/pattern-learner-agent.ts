export type EditingPatternEvidence = {
  attempts: number;
  successes: number;
  avgActualMinutes: number;
};

export function deriveEditingBlockPattern(evidence: EditingPatternEvidence) {
  return {
    patternKey: "editing_blocks_over_120_min_fail",
    evidence,
    recommendation:
      evidence.successes <= 2
        ? "Plan editing in 60-minute blocks with 10-minute breaks."
        : "Long editing blocks are acceptable when success history supports them."
  };
}

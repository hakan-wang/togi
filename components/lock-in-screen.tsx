import { RealityConfirmation } from "@/components/reality-confirmation";
import { ScreenShareCapture } from "@/components/screen-share-capture";

export function LockInScreen() {
  const plannedBlockId = "demo-block";
  return (
    <div className="max-w-3xl space-y-4">
      <h1 className="text-3xl font-semibold">Screen accountability</h1>
      <p className="text-sm text-steel">Share a screen, window, or tab for this lock-in block.</p>
      <ScreenShareCapture plannedBlockId={plannedBlockId} />
      <RealityConfirmation plannedBlockId={plannedBlockId} />
    </div>
  );
}

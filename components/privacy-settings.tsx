export function PrivacySettings() {
  return (
    <section className="max-w-2xl rounded-md border border-line bg-white p-4">
      <h2 className="text-lg font-semibold">Privacy defaults</h2>
      <div className="mt-4 space-y-3 text-sm">
        <label className="flex items-center gap-2">
          <input type="checkbox" name="debugFrames" />
          Temporary debug frames
        </label>
        <p>No raw frame storage by default</p>
        <p>No monitoring outside lock-in sessions</p>
        <p>Stored forever: summaries only</p>
      </div>
    </section>
  );
}

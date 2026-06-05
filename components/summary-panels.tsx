const panels = [
  { label: "Planned", value: "6.0h" },
  { label: "Confirmed reality", value: "4.7h" },
  { label: "Gap", value: "1.3h" }
];

export function SummaryPanels() {
  return (
    <section className="grid gap-3 sm:grid-cols-3">
      {panels.map((panel) => (
        <div key={panel.label} className="rounded-md border border-line bg-white p-4">
          <p className="text-sm text-steel">{panel.label}</p>
          <p className="mt-2 text-2xl font-semibold">{panel.value}</p>
        </div>
      ))}
    </section>
  );
}

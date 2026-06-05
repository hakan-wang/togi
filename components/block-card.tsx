type BlockCardProps = {
  title: string;
  time: string;
  intention: string;
  status: "planned" | "logged" | "missed";
};

export function BlockCard({ title, time, intention, status }: BlockCardProps) {
  return (
    <article className="rounded-md border border-line bg-white p-4">
      <div className="flex items-start justify-between gap-3">
        <div>
          <h3 className="text-base font-semibold">{title}</h3>
          <p className="mt-1 text-sm text-steel">{time}</p>
        </div>
        <span className="rounded border border-line px-2 py-1 text-xs capitalize">{status}</span>
      </div>
      <p className="mt-3 text-sm">{intention}</p>
    </article>
  );
}

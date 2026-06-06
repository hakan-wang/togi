import { createFileRoute } from "@tanstack/react-router";
import { useEffect, useRef, useState } from "react";
import mascotImg from "@/assets/mascot.png";

export const Route = createFileRoute("/companion")({
  head: () => ({ meta: [{ title: "Bogi · Desktop companion (UI mockup)" }] }),
  component: Companion,
});

type Msg = { from: "bogi" | "you"; text: string };

const GREETING = "hey. want to know where your time actually went today?";
const BOGI_REPLIES = [
  "so far today: 2h editing, then about 40 minutes wandered off to TikTok.",
  "you blocked 1 to 4 for school work. you are 25 minutes in. still on it?",
  "honestly, you planned 6 hours of focus and you are at about 3. want the breakdown?",
  "the email hour you set this morning never happened. move it to tonight?",
];

function Companion() {
  const [open, setOpen] = useState(false);
  const [messages, setMessages] = useState<Msg[]>([{ from: "bogi", text: GREETING }]);
  const [draft, setDraft] = useState("");
  const [pos, setPos] = useState({ x: 0, y: 0 });
  const replyIdx = useRef(0);
  const scrollRef = useRef<HTMLDivElement>(null);
  const movedRef = useRef(false);
  const startRef = useRef<{ sx: number; sy: number; bx: number; by: number } | null>(null);

  useEffect(() => {
    scrollRef.current?.scrollTo({ top: scrollRef.current.scrollHeight, behavior: "smooth" });
  }, [messages, open]);

  const send = () => {
    const t = draft.trim();
    if (!t) return;
    setDraft("");
    setMessages((m) => [...m, { from: "you", text: t }]);
    const reply = BOGI_REPLIES[replyIdx.current % BOGI_REPLIES.length];
    replyIdx.current += 1;
    window.setTimeout(() => setMessages((m) => [...m, { from: "bogi", text: reply }]), 600);
  };

  const onPointerDown = (e: React.PointerEvent) => {
    movedRef.current = false;
    startRef.current = { sx: e.clientX, sy: e.clientY, bx: pos.x, by: pos.y };
    const move = (ev: PointerEvent) => {
      const s = startRef.current;
      if (!s) return;
      const dx = ev.clientX - s.sx;
      const dy = ev.clientY - s.sy;
      if (Math.abs(dx) > 4 || Math.abs(dy) > 4) movedRef.current = true;
      setPos({ x: s.bx + dx, y: s.by + dy });
    };
    const up = () => {
      window.removeEventListener("pointermove", move);
      window.removeEventListener("pointerup", up);
      startRef.current = null;
    };
    window.addEventListener("pointermove", move);
    window.addEventListener("pointerup", up);
  };

  const onBogiClick = () => {
    if (movedRef.current) {
      movedRef.current = false;
      return;
    }
    setOpen((o) => !o);
  };

  return (
    <div className="companion-desktop relative min-h-screen w-full overflow-hidden">
      <div className="companion-menubar">
        <div className="flex items-center gap-4">
          <span className="font-semibold">Bogi</span>
          <span className="opacity-60">File</span>
          <span className="opacity-60">Edit</span>
          <span className="opacity-60">View</span>
        </div>
        <div className="flex items-center gap-3 opacity-75">
          <span>100%</span>
          <span>Sat 13:42</span>
        </div>
      </div>

      <p className="companion-hint">
        a mockup of Bogi living on your desktop. drag him around, click him to chat.
      </p>

      <div className="companion-anchor" style={{ transform: `translate(${pos.x}px, ${pos.y}px)` }}>
        {open && (
          <div className="companion-chat">
            <div className="companion-chat-head">
              <img src={mascotImg} alt="" className="h-6 w-6 object-contain" />
              <span>Bogi</span>
              <button className="companion-x" onClick={() => setOpen(false)} aria-label="close">
                ×
              </button>
            </div>
            <div ref={scrollRef} className="companion-msgs">
              {messages.map((m, i) => (
                <div
                  key={i}
                  className={
                    m.from === "you"
                      ? "companion-bubble companion-bubble--you"
                      : "companion-bubble companion-bubble--bogi"
                  }
                >
                  {m.text}
                </div>
              ))}
            </div>
            <form
              className="companion-input"
              onSubmit={(e) => {
                e.preventDefault();
                send();
              }}
            >
              <input
                value={draft}
                onChange={(e) => setDraft(e.target.value)}
                placeholder="ask where your time went..."
              />
              <button type="submit" aria-label="send">
                ↑
              </button>
            </form>
          </div>
        )}

        <img
          src={mascotImg}
          alt="Bogi"
          className="companion-bogi monster-float"
          draggable={false}
          onPointerDown={onPointerDown}
          onClick={onBogiClick}
        />
      </div>
    </div>
  );
}

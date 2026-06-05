"use client";

import { useRef, useState } from "react";
import { Mic, Square } from "lucide-react";

export function VoiceCommand() {
  const recorderRef = useRef<MediaRecorder | null>(null);
  const chunksRef = useRef<Blob[]>([]);
  const [status, setStatus] = useState("idle");
  const [transcript, setTranscript] = useState("");

  async function start() {
    const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
    const recorder = new MediaRecorder(stream);
    recorderRef.current = recorder;
    chunksRef.current = [];
    recorder.ondataavailable = (event) => chunksRef.current.push(event.data);
    recorder.onstop = sendAudio;
    recorder.start();
    setStatus("recording");
  }

  function stop() {
    recorderRef.current?.stop();
    setStatus("transcribing");
  }

  async function sendAudio() {
    const blob = new Blob(chunksRef.current, { type: "audio/webm" });
    const form = new FormData();
    form.append("audio", blob);
    const response = await fetch("/api/voice/transcribe", { method: "POST", body: form });
    const data = await response.json();
    setTranscript(String(data.text ?? ""));
    setStatus("idle");
  }

  return (
    <section className="rounded-md border border-line bg-white p-4">
      <div className="flex gap-2">
        <button className="inline-flex items-center gap-2 rounded-md bg-ink px-4 py-2 text-sm font-medium text-white" type="button" onClick={start}>
          <Mic className="h-4 w-4" /> Talk
        </button>
        <button className="inline-flex items-center gap-2 rounded-md border border-line px-4 py-2 text-sm font-medium" type="button" onClick={stop}>
          <Square className="h-4 w-4" /> Stop
        </button>
      </div>
      <p className="mt-2 text-sm text-steel">{status}</p>
      {transcript ? <p className="mt-3 text-sm">{transcript}</p> : null}
    </section>
  );
}

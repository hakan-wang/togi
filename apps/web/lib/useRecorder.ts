/* ============================================================
   Togi — useRecorder: a small MediaRecorder hook for voice check-ins.
   Mic only opens when start() is called (never automatically — per the addendum).
   Exposes a live `level` (0..1) for the waveform, pause/resume, stop→Blob, cancel.
   ============================================================ */
"use client";
import { useCallback, useRef, useState } from "react";

function pickMime(): string {
  const cands = ["audio/webm;codecs=opus", "audio/webm", "audio/mp4", "audio/ogg"];
  if (typeof MediaRecorder === "undefined") return "";
  for (const c of cands) { try { if (MediaRecorder.isTypeSupported(c)) return c; } catch { /* ignore */ } }
  return "";
}

export interface Recorder {
  isRecording: boolean;
  isPaused: boolean;
  level: number;
  error: string | null;
  start: () => Promise<void>;
  pause: () => void;
  resume: () => void;
  stop: () => Promise<Blob | null>;
  cancel: () => void;
}

export function useRecorder(): Recorder {
  const [isRecording, setRecording] = useState(false);
  const [isPaused, setPaused] = useState(false);
  const [level, setLevel] = useState(0);
  const [error, setError] = useState<string | null>(null);

  const mrRef = useRef<MediaRecorder | null>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const chunksRef = useRef<Blob[]>([]);
  const acRef = useRef<AudioContext | null>(null);
  const rafRef = useRef<number | null>(null);

  const teardown = useCallback(() => {
    if (rafRef.current) cancelAnimationFrame(rafRef.current);
    rafRef.current = null;
    streamRef.current?.getTracks().forEach((t) => t.stop());
    streamRef.current = null;
    acRef.current?.close().catch(() => {});
    acRef.current = null;
    mrRef.current = null;
    setLevel(0);
    setRecording(false);
    setPaused(false);
  }, []);

  const start = useCallback(async () => {
    setError(null);
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      streamRef.current = stream;
      chunksRef.current = [];
      const mime = pickMime();
      const mr = new MediaRecorder(stream, mime ? { mimeType: mime } : undefined);
      mr.ondataavailable = (e) => { if (e.data && e.data.size) chunksRef.current.push(e.data); };
      mr.start(100);
      mrRef.current = mr;
      setRecording(true);
      setPaused(false);

      // live level meter for the waveform
      try {
        const AC = (window.AudioContext || (window as any).webkitAudioContext);
        const ac = new AC();
        acRef.current = ac;
        const src = ac.createMediaStreamSource(stream);
        const analyser = ac.createAnalyser();
        analyser.fftSize = 256;
        src.connect(analyser);
        const buf = new Uint8Array(analyser.frequencyBinCount);
        const tick = () => {
          analyser.getByteTimeDomainData(buf);
          let sum = 0;
          for (let i = 0; i < buf.length; i++) { const v = (buf[i] - 128) / 128; sum += v * v; }
          setLevel(Math.min(1, Math.sqrt(sum / buf.length) * 3));
          rafRef.current = requestAnimationFrame(tick);
        };
        tick();
      } catch { /* level meter is optional */ }
    } catch (e: any) {
      setError(e?.name === "NotAllowedError" ? "Microphone permission was denied." : "Couldn’t start the microphone.");
      teardown();
      throw e;
    }
  }, [teardown]);

  const pause = useCallback(() => {
    try { mrRef.current?.state === "recording" && mrRef.current.pause(); setPaused(true); } catch { /* ignore */ }
  }, []);
  const resume = useCallback(() => {
    try { mrRef.current?.state === "paused" && mrRef.current.resume(); setPaused(false); } catch { /* ignore */ }
  }, []);

  const stop = useCallback((): Promise<Blob | null> => {
    return new Promise((resolve) => {
      const mr = mrRef.current;
      if (!mr) { resolve(null); return; }
      mr.onstop = () => {
        const blob = chunksRef.current.length ? new Blob(chunksRef.current, { type: chunksRef.current[0].type || "audio/webm" }) : null;
        teardown();
        resolve(blob);
      };
      try { mr.stop(); } catch { teardown(); resolve(null); }
    });
  }, [teardown]);

  const cancel = useCallback(() => {
    const mr = mrRef.current;
    if (mr) { mr.onstop = () => teardown(); try { mr.stop(); } catch { teardown(); } }
    else teardown();
  }, [teardown]);

  return { isRecording, isPaused, level, error, start, pause, resume, stop, cancel };
}

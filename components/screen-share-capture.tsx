"use client";

import { useRef, useState } from "react";
import { Monitor, Square } from "lucide-react";
import { targetCanvasSize } from "@/lib/screen/frame-sampler";
import { hashBlob } from "@/lib/screen/image-hash";

export function ScreenShareCapture({ plannedBlockId }: { plannedBlockId: string }) {
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const timerRef = useRef<number | null>(null);
  const [status, setStatus] = useState("idle");

  async function start() {
    const stream = await navigator.mediaDevices.getDisplayMedia({ video: true, audio: false });
    if (videoRef.current) {
      videoRef.current.srcObject = stream;
      await videoRef.current.play();
    }
    setStatus("sharing");
    timerRef.current = window.setInterval(sampleFrame, 15000);
  }

  function stop() {
    if (timerRef.current) window.clearInterval(timerRef.current);
    const stream = videoRef.current?.srcObject as MediaStream | null;
    stream?.getTracks().forEach((track) => track.stop());
    setStatus("stopped");
  }

  async function sampleFrame() {
    const video = videoRef.current;
    if (!video || video.videoWidth === 0) return;
    const size = targetCanvasSize({ width: video.videoWidth, height: video.videoHeight, targetWidth: 1024 });
    const canvas = document.createElement("canvas");
    canvas.width = size.width;
    canvas.height = size.height;
    const context = canvas.getContext("2d");
    if (!context) return;
    context.drawImage(video, 0, 0, size.width, size.height);
    const blob = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, "image/jpeg", 0.5));
    if (!blob) return;
    const hash = await hashBlob(blob);
    const form = new FormData();
    form.append("plannedBlockId", plannedBlockId);
    form.append("capturedAt", new Date().toISOString());
    form.append("hash", hash);
    form.append("frame", blob);
    await fetch("/api/screen/batch", { method: "POST", body: form });
  }

  return (
    <section className="rounded-md border border-line bg-white p-4">
      <video ref={videoRef} className="hidden" muted playsInline />
      <div className="flex gap-2">
        <button className="inline-flex items-center gap-2 rounded-md bg-ink px-4 py-2 text-sm font-medium text-white" type="button" onClick={start}>
          <Monitor className="h-4 w-4" /> Share screen
        </button>
        <button className="inline-flex items-center gap-2 rounded-md border border-line px-4 py-2 text-sm font-medium" type="button" onClick={stop}>
          <Square className="h-4 w-4" /> Stop
        </button>
      </div>
      <p className="mt-2 text-sm text-steel">{status}</p>
    </section>
  );
}

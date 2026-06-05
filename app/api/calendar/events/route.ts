import { NextResponse } from "next/server";
import { toGoogleCalendarEvent } from "@/lib/calendar/google-calendar";
import { plannedBlockSchema } from "@/lib/zod/contracts";

export async function POST(request: Request) {
  const block = plannedBlockSchema.parse(await request.json());
  return NextResponse.json({ event: toGoogleCalendarEvent(block) });
}

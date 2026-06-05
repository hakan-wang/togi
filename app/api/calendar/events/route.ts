import { NextResponse } from "next/server";
import { createGoogleCalendarClient, insertGoogleCalendarEvent, toGoogleCalendarEvent } from "@/lib/calendar/google-calendar";
import { savePlannedBlock } from "@/lib/db/bogi-store";
import { createServerSupabaseClient } from "@/lib/db/server";
import { plannedBlockSchema } from "@/lib/zod/contracts";

export async function POST(request: Request) {
  const body = await request.json();
  const userId = String(body.userId ?? "");
  const block = plannedBlockSchema.parse(body);
  const event = toGoogleCalendarEvent(block);
  const googleCalendarEventId = userId
    ? await insertGoogleCalendarEvent(createGoogleCalendarClient(), block)
    : null;
  const savedBlock = userId
    ? await savePlannedBlock(await createServerSupabaseClient(), userId, block, googleCalendarEventId)
    : null;
  return NextResponse.json({ event, googleCalendarEventId, savedBlock });
}

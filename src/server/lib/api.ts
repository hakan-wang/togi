import { NextResponse } from "next/server";
import { z } from "zod";
import { AppError } from "@/server/lib/errors";
import { getUserFromRequest } from "@/server/auth/user";

export const json = (body: unknown, status = 200) => NextResponse.json(body, { status });

export const parseJson = async <S extends z.ZodTypeAny>(request: Request, schema: S): Promise<z.infer<S>> => {
  const body = await request.json();
  return schema.parse(body);
};

export const withUser = async <T>(request: Request, handler: (userId: string) => Promise<T>) => {
  try {
    const user = await getUserFromRequest(request);
    return json(await handler(user.id));
  } catch (error) {
    return errorResponse(error);
  }
};

export const errorResponse = (error: unknown) => {
  if (error instanceof z.ZodError) {
    return json({ error: "Validation failed", issues: error.issues }, 400);
  }
  if (error instanceof AppError) {
    return json({ error: error.message }, error.status);
  }
  const message = error instanceof Error ? error.message : "Unknown error";
  return json({ error: message }, 500);
};

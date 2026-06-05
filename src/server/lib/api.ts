import { NextResponse } from "next/server";
import { z } from "zod";
import { AppError } from "@/server/lib/errors";
import { getUserFromRequest } from "@/server/auth/user";

export const json = (body: unknown, status = 200) => NextResponse.json(body, { status });

export const jsonValidated = <S extends z.ZodTypeAny>(schema: S, body: unknown, status = 200) => {
  try {
    return json(schema.parse(body), status);
  } catch (error) {
    if (error instanceof z.ZodError) {
      return json({ error: "Response validation failed", issues: error.issues }, 500);
    }
    throw error;
  }
};

export const parseJson = async <S extends z.ZodTypeAny>(request: Request, schema: S): Promise<z.infer<S>> => {
  const body = await request.json();
  return schema.parse(body);
};

export const withUser = async <T, S extends z.ZodTypeAny>(
  request: Request,
  handler: (userId: string) => Promise<T>,
  responseSchema?: S
) => {
  try {
    const user = await getUserFromRequest(request);
    const body = await handler(user.id);
    return responseSchema ? jsonValidated(responseSchema, body) : json(body);
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

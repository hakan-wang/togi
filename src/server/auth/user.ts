import { AppError } from "@/server/lib/errors";
import { createServerSupabaseClient } from "@/server/db/supabase";

export type AuthenticatedUser = {
  id: string;
  email?: string;
};

export const getUserFromRequest = async (request: Request): Promise<AuthenticatedUser> => {
  const header = request.headers.get("authorization");
  const token = header?.startsWith("Bearer ") ? header.slice("Bearer ".length).trim() : null;
  if (!token) throw new AppError("Missing bearer token", 401);

  const supabase = createServerSupabaseClient();
  if (!supabase) {
    return { id: token };
  }

  const { data, error } = await supabase.auth.getUser(token);
  if (error || !data.user) throw new AppError("Invalid bearer token", 401);

  return {
    id: data.user.id,
    email: data.user.email
  };
};

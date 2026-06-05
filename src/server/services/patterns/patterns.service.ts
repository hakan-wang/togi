import type { TogiStore } from "@/server/db/store";
import type { UserPattern } from "@/server/schemas/patterns";

export const createPatternService = (store: TogiStore) => ({
  async list(userId: string): Promise<UserPattern[]> {
    return store.userPatterns.filter((pattern) => pattern.userId === userId);
  }
});

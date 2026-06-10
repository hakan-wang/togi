import Database from "better-sqlite3";

export type DB = Database.Database;

/** Open the app's SQLite file read-only. WAL lets us read without blocking the writer. */
export function openReadOnly(path: string): DB {
  const db = new Database(path, { readonly: true, fileMustExist: true });
  db.pragma("query_only = true");
  return db;
}

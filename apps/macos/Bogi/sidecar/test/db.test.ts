import { test, expect } from "vitest";
import Database from "better-sqlite3";
import { openReadOnly } from "../src/db.js";

test("openReadOnly can query but not write", () => {
  const path = `/tmp/bogi-db-${process.pid}.sqlite`;
  const seed = new Database(path);
  seed.exec("CREATE TABLE t (x INTEGER); INSERT INTO t VALUES (1);");
  seed.close();

  const db = openReadOnly(path);
  expect(db.prepare("SELECT x FROM t").get()).toEqual({ x: 1 });
  expect(() => db.prepare("INSERT INTO t VALUES (2)").run()).toThrow();
});

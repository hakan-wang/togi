import { test, expect } from "vitest";
import { PERSONA } from "../src/persona.js";

test("persona instructs goal, journal, and check-in behaviour", () => {
  expect(PERSONA).toContain("manage_goal");
  expect(PERSONA).toContain("log_journal");
  expect(PERSONA).toContain("due_check_ins");
  expect(PERSONA).not.toContain("—"); // never em-dashes
});

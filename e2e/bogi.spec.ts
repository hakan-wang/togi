import { expect, test } from "@playwright/test";

test("dashboard and lock-in pages render", async ({ page }) => {
  await page.goto("/dashboard");
  await expect(page.getByRole("heading", { name: "Today" })).toBeVisible();
  await page.goto("/lock-in");
  await expect(page.getByRole("heading", { name: "Screen accountability" })).toBeVisible();
  await expect(page.getByRole("button", { name: /Share screen/ })).toBeVisible();
});

test("home links to dashboard and lock-in", async ({ page }) => {
  await page.goto("/");
  await expect(page.getByRole("link", { name: "Open dashboard" })).toHaveAttribute("href", "/dashboard");
  await expect(page.getByRole("link", { name: "Start lock-in" })).toHaveAttribute("href", "/lock-in");
});

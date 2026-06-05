import { render, screen } from "@testing-library/react";
import { createElement } from "react";
import { describe, expect, it } from "vitest";
import { AppShell } from "@/components/app-shell";

describe("AppShell", () => {
  it("renders primary Bogi navigation", () => {
    render(createElement(AppShell, null, createElement("div", null, "Dashboard content")));
    expect(screen.getByRole("link", { name: "Dashboard" })).toHaveAttribute("href", "/dashboard");
    expect(screen.getByRole("link", { name: "Lock-in" })).toHaveAttribute("href", "/lock-in");
    expect(screen.getByText("Dashboard content")).toBeInTheDocument();
  });
});

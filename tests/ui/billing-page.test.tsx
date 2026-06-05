import { render, screen } from "@testing-library/react";
import { createElement } from "react";
import { describe, expect, it } from "vitest";
import BillingPage from "@/app/(app)/billing/page";

describe("BillingPage", () => {
  it("renders founding plan CTA", () => {
    render(createElement(BillingPage));
    expect(screen.getByRole("heading", { name: "Founding plan" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Join founding plan" })).toBeInTheDocument();
  });
});

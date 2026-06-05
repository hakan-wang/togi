import { render, screen } from "@testing-library/react";
import { createElement } from "react";
import { describe, expect, it } from "vitest";
import { PrivacySettings } from "@/components/privacy-settings";

describe("PrivacySettings", () => {
  it("defaults raw frame storage off", () => {
    render(createElement(PrivacySettings));
    const checkbox = screen.getByRole("checkbox", { name: "Temporary debug frames" });
    expect(checkbox).not.toBeChecked();
    expect(screen.getByText("Stored forever: summaries only")).toBeInTheDocument();
  });
});

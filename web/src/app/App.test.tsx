import { render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { describe, expect, it } from "vitest";

import { App } from "./App";

describe("App", () => {
  it("renders the signed-out MathLand shell in Korean", () => {
    render(
      <MemoryRouter>
        <App />
      </MemoryRouter>,
    );

    expect(screen.getByRole("heading", { name: "MathLand 보호자" })).toBeVisible();
    expect(screen.getByRole("link", { name: "이메일로 시작하기" })).toHaveAttribute(
      "href",
      "/login",
    );
  });
});

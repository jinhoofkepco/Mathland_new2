import { render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { describe, expect, it } from "vitest";

import { App } from "./App";
import { MathLandRouter } from "./router";

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

  it("opens a GitHub Pages deep link through the URL hash", () => {
    window.location.hash = "#/login";

    render(
      <MathLandRouter>
        <App />
      </MathLandRouter>,
    );

    expect(screen.getByRole("heading", { name: "보호자 로그인" })).toBeVisible();
  });
});

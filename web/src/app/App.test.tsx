import { render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { describe, expect, it } from "vitest";

import { App } from "./App";
import { MathLandRouter } from "./router";
import { CloudProvider } from "../cloud/cloud_provider";
import { FakeCloud } from "../cloud/fake_cloud";

const cloud = new FakeCloud();

describe("App", () => {
  it("renders the signed-out MathLand shell in Korean", () => {
    render(
      <CloudProvider cloud={cloud}>
        <MemoryRouter>
          <App />
        </MemoryRouter>
      </CloudProvider>,
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
      <CloudProvider cloud={cloud}>
        <MathLandRouter>
          <App />
        </MathLandRouter>
      </CloudProvider>,
    );

    expect(screen.getByRole("heading", { name: "보호자 로그인" })).toBeVisible();
  });
});

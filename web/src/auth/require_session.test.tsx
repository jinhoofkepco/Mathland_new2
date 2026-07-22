import { render, screen } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { describe, expect, it } from "vitest";

import { CloudProvider } from "../cloud/cloud_provider";
import { FakeCloud } from "../cloud/fake_cloud";
import { AuthProvider } from "./auth_provider";
import { RequireSession } from "./require_session";

describe("RequireSession", () => {
  it("sends a first-time guardian to onboarding without exposing protected content", async () => {
    const cloud = new FakeCloud({
      session: { status: "onboarding", userId: "00000000-0000-4000-8000-000000000099" },
      families: [], children: [], dashboards: {},
    });
    render(
      <CloudProvider cloud={cloud}>
        <MemoryRouter initialEntries={["/devices"]}>
          <AuthProvider>
            <Routes>
              <Route path="/devices" element={<RequireSession><h1>보호 내용</h1></RequireSession>} />
              <Route path="/onboarding" element={<h1>처음 설정</h1>} />
            </Routes>
          </AuthProvider>
        </MemoryRouter>
      </CloudProvider>,
    );

    expect(await screen.findByRole("heading", { name: "처음 설정" })).toBeVisible();
    expect(screen.queryByRole("heading", { name: "보호 내용" })).not.toBeInTheDocument();
  });
});

import { render, screen } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { describe, expect, it } from "vitest";

import { CloudProvider } from "../cloud/cloud_provider";
import { FakeCloud } from "../cloud/fake_cloud";
import { AuthProvider } from "./auth_provider";
import { RequireFamily } from "./require_family";

function renderOwner(familyStatus: "ready" | "onboarding" | "unauthorized") {
  const cloud = new FakeCloud({
    session: {
      status: "authenticated",
      userId: "00000000-0000-4000-8000-000000000099",
      role: "owner",
      familyStatus,
    },
    families: [], children: [], dashboards: {},
  });
  render(
    <CloudProvider cloud={cloud}>
      <MemoryRouter initialEntries={["/devices"]}>
        <AuthProvider>
          <Routes>
            <Route path="/devices" element={<RequireFamily><h1>기기 연결</h1></RequireFamily>} />
            <Route path="/onboarding" element={<h1>처음 설정</h1>} />
          </Routes>
        </AuthProvider>
      </MemoryRouter>
    </CloudProvider>,
  );
}

describe("RequireFamily", () => {
  it("routes a global Studio owner with no family into guardian onboarding", async () => {
    renderOwner("onboarding");
    expect(await screen.findByRole("heading", { name: "처음 설정" })).toBeVisible();
  });

  it("allows a global Studio owner who also has a guardian family", async () => {
    renderOwner("ready");
    expect(await screen.findByRole("heading", { name: "기기 연결" })).toBeVisible();
  });
});

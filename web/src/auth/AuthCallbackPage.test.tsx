import { render, screen } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { describe, expect, it } from "vitest";

import type { SessionState } from "../cloud/cloud_port";
import { CloudProvider } from "../cloud/cloud_provider";
import { FakeCloud } from "../cloud/fake_cloud";
import { AuthCallbackPage } from "./AuthCallbackPage";
import { AuthProvider } from "./auth_provider";
import { RequireFamily } from "./require_family";

function renderCallback(session: SessionState, next = "/devices") {
  const cloud = new FakeCloud({ session, families: [], children: [], dashboards: {} });
  render(
    <CloudProvider cloud={cloud}>
      <MemoryRouter initialEntries={[`/auth/callback?next=${encodeURIComponent(next)}`]}>
        <AuthProvider>
          <Routes>
            <Route path="/auth/callback" element={<AuthCallbackPage />} />
            <Route path="/login" element={<h1>보호자 로그인</h1>} />
            <Route path="/studio" element={<h1>콘텐츠 스튜디오</h1>} />
            <Route path="/devices" element={<RequireFamily><h1>기기 연결</h1></RequireFamily>} />
            <Route path="/onboarding" element={<h1>처음 설정</h1>} />
          </Routes>
        </AuthProvider>
      </MemoryRouter>
    </CloudProvider>,
  );
}

describe("AuthCallbackPage", () => {
  it("returns a signed-out callback to login instead of spinning forever", async () => {
    renderCallback({ status: "signed_out" });
    expect(await screen.findByRole("heading", { name: "보호자 로그인" })).toBeVisible();
  });

  it("renders a terminal family permission message for unauthorized accounts", async () => {
    renderCallback({
      status: "unauthorized",
      userId: "00000000-0000-4000-8000-000000000099",
    });
    expect(await screen.findByRole("heading", { name: "가족 권한을 확인해 주세요" })).toBeVisible();
  });

  it("honors a Studio deep link for a global owner without a guardian family", async () => {
    renderCallback({
      status: "authenticated",
      userId: "00000000-0000-4000-8000-000000000099",
      role: "owner",
      familyStatus: "onboarding",
    }, "/studio");
    expect(await screen.findByRole("heading", { name: "콘텐츠 스튜디오" })).toBeVisible();
  });

  it("lets a family route enforce onboarding after the callback", async () => {
    renderCallback({
      status: "authenticated",
      userId: "00000000-0000-4000-8000-000000000099",
      role: "owner",
      familyStatus: "onboarding",
    }, "/devices");
    expect(await screen.findByRole("heading", { name: "처음 설정" })).toBeVisible();
  });
});

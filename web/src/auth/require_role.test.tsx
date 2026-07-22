import { render, screen } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { describe, expect, it } from "vitest";

import { CloudProvider } from "../cloud/cloud_provider";
import { FakeCloud } from "../cloud/fake_cloud";
import { AuthProvider } from "./auth_provider";
import { RequireRole } from "./require_role";

function renderRole(role: "guardian" | "editor" | "owner", allow: Array<typeof role>) {
  const cloud = new FakeCloud({
    session: {
      status: "authenticated",
      userId: "00000000-0000-4000-8000-000000000001",
      role,
      familyStatus: role === "guardian" ? "ready" : "unauthorized",
    },
    families: [],
    children: [],
    dashboards: {},
  });
  return render(
    <CloudProvider cloud={cloud}>
      <MemoryRouter initialEntries={["/studio"]}>
        <AuthProvider>
          <Routes>
            <Route
              path="/studio"
              element={
                <RequireRole allow={allow}>
                  <h1>콘텐츠 스튜디오</h1>
                </RequireRole>
              }
            />
          </Routes>
        </AuthProvider>
      </MemoryRouter>
    </CloudProvider>,
  );
}

describe("RequireRole", () => {
  it("shows a 403 page without rendering privileged children", async () => {
    renderRole("guardian", ["editor", "owner"]);
    expect(await screen.findByRole("heading", { name: "접근할 수 없는 화면입니다" })).toBeVisible();
    expect(screen.queryByText("콘텐츠 스튜디오")).not.toBeInTheDocument();
  });

  it("allows editors into draft routes", async () => {
    renderRole("editor", ["editor", "owner"]);
    expect(await screen.findByRole("heading", { name: "콘텐츠 스튜디오" })).toBeVisible();
  });
});

import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { describe, expect, it, vi } from "vitest";

import { AuthProvider } from "../auth/auth_provider";
import { CloudProvider } from "../cloud/cloud_provider";
import { FakeCloud } from "../cloud/fake_cloud";
import { OnboardingPage } from "./OnboardingPage";

const USER_ID = "00000000-0000-4000-8000-000000000099";

class OnboardingCloud extends FakeCloud {
  #onboarded = false;
  readonly bootstrap = vi.fn(async (_input: { familyName: string; childNickname: string }) => ({
    familyId: "10000000-0000-4000-8000-000000000099",
    profileId: "20000000-0000-4000-8000-000000000099",
  }));

  constructor() {
    super({
      session: { status: "onboarding", userId: USER_ID },
      families: [],
      children: [],
      dashboards: {},
    });
  }

  override async session() {
    return this.#onboarded
      ? ({ status: "authenticated", userId: USER_ID, role: "guardian", familyStatus: "ready" } as const)
      : ({ status: "onboarding", userId: USER_ID } as const);
  }

  override async bootstrapGuardian(input: { familyName: string; childNickname: string }) {
    const result = await this.bootstrap(input);
    this.#onboarded = true;
    return result;
  }
}

function renderOnboarding(cloud = new OnboardingCloud()) {
  render(
    <CloudProvider cloud={cloud}>
      <MemoryRouter initialEntries={["/onboarding"]}>
        <AuthProvider>
          <Routes>
            <Route path="/onboarding" element={<OnboardingPage />} />
            <Route path="/devices" element={<h1>기기 연결</h1>} />
          </Routes>
        </AuthProvider>
      </MemoryRouter>
    </CloudProvider>,
  );
  return cloud;
}

describe("OnboardingPage", () => {
  it("creates the first family and child, then continues to device pairing", async () => {
    const cloud = renderOnboarding();

    expect(await screen.findByRole("heading", { name: "우리 가족 탐험 시작하기" })).toBeVisible();
    await userEvent.type(screen.getByLabelText("가족 이름"), "모아네 가족");
    await userEvent.type(screen.getByLabelText("아이 별명"), "모아");
    await userEvent.click(screen.getByRole("button", { name: "가족 만들고 기기 연결하기" }));

    expect(cloud.bootstrap).toHaveBeenCalledWith({ familyName: "모아네 가족", childNickname: "모아" });
    expect(await screen.findByRole("heading", { name: "기기 연결" })).toBeVisible();
  });

  it("validates both names before touching the cloud", async () => {
    const cloud = renderOnboarding();
    await screen.findByRole("heading", { name: "우리 가족 탐험 시작하기" });
    await userEvent.click(screen.getByRole("button", { name: "가족 만들고 기기 연결하기" }));

    expect(await screen.findByRole("alert")).toHaveTextContent("가족 이름과 아이 별명을 입력해 주세요");
    expect(cloud.bootstrap).not.toHaveBeenCalled();
  });
});

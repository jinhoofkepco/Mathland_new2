import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter } from "react-router-dom";
import { describe, expect, it } from "vitest";

import { CloudProvider } from "../cloud/cloud_provider";
import { FakeCloud } from "../cloud/fake_cloud";
import { DashboardPage } from "./DashboardPage";

const FAMILY = "10000000-0000-4000-8000-000000000001";
const CHILD = "20000000-0000-4000-8000-000000000001";

function demoCloud() {
  return new FakeCloud({
    session: { status: "authenticated", userId: "00000000-0000-4000-8000-000000000001", role: "guardian" },
    families: [{ id: FAMILY, name: "모아 가족", role: "guardian" }],
    children: [{ id: CHILD, familyId: FAMILY, nickname: "서아", lastSyncAt: "2030-01-01T00:00:00.000Z" }],
    dashboards: {
      [FAMILY]: {
        familyId: FAMILY,
        generatedAt: "2030-01-01T00:00:00.000Z",
        sessions: [
          { runId: "run-1", profileId: CHILD, startedAt: "2030-01-01T00:00:00.000Z", score: 8 },
        ],
        activities: [
          { profileId: CHILD, activityId: "addition_ones", answerCount: 10, correctCount: 8, averageResponseDurationMs: 3200, lastPlayedAt: "2030-01-01T00:00:00.000Z" },
        ],
        errors: [
          { profileId: CHILD, activityId: "addition_ones", generatorId: "addition_v1", bandId: "practice", incorrectCount: 2, lastIncorrectAt: "2030-01-01T00:00:00.000Z" },
        ],
        rewards: [
          { profileId: CHILD, rewardId: "apple", quantity: 14, updatedAt: "2030-01-01T00:00:00.000Z" },
        ],
      },
    },
  });
}

describe("DashboardPage", () => {
  it("renders family-scoped learning aggregates and child filters", async () => {
    render(
      <CloudProvider cloud={demoCloud()}>
        <MemoryRouter>
          <DashboardPage />
        </MemoryRouter>
      </CloudProvider>,
    );

    expect(await screen.findByRole("heading", { name: "서아의 탐험 현황" })).toBeVisible();
    expect(await screen.findByText("80%")).toBeVisible();
    expect(screen.getByText("평균 3.2초")).toBeVisible();
    expect(screen.getByText("사과 14개")).toBeVisible();
    expect(screen.getByText("연습 단계에서 2번 어려워했어요")).toBeVisible();
    await userEvent.click(screen.getByRole("button", { name: "최근 30일" }));
    expect(screen.getByRole("button", { name: "최근 30일" })).toHaveAttribute("aria-pressed", "true");
  });
});

import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter } from "react-router-dom";
import { describe, expect, it } from "vitest";

import { CloudProvider } from "../cloud/cloud_provider";
import { FakeCloud } from "../cloud/fake_cloud";
import { DevicesPage } from "./DevicesPage";

const FAMILY = "10000000-0000-4000-8000-000000000001";
const CHILD = "20000000-0000-4000-8000-000000000001";

describe("DevicesPage", () => {
  it("shows a one-time pairing code and removes it when closed", async () => {
    const cloud = new FakeCloud({
      session: { status: "authenticated", userId: "00000000-0000-4000-8000-000000000001", role: "guardian", familyStatus: "ready" },
      families: [{ id: FAMILY, name: "모아 가족", role: "guardian" }],
      children: [{ id: CHILD, familyId: FAMILY, nickname: "서아", lastSyncAt: null }],
      dashboards: {},
    });
    render(
      <CloudProvider cloud={cloud}>
        <MemoryRouter><DevicesPage /></MemoryRouter>
      </CloudProvider>,
    );

    await userEvent.click(await screen.findByRole("button", { name: "서아 기기 연결" }));
    expect(screen.getByText("482 913")).toBeVisible();
    expect(screen.getByText(/10분 안에/)).toBeVisible();
    await userEvent.click(screen.getByRole("button", { name: "연결 코드 닫기" }));
    expect(screen.queryByText("482 913")).not.toBeInTheDocument();
  });
});

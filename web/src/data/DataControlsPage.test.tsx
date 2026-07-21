import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter } from "react-router-dom";
import { describe, expect, it, vi } from "vitest";

import { CloudProvider } from "../cloud/cloud_provider";
import { FakeCloud } from "../cloud/fake_cloud";
import { DataControlsPage } from "./DataControlsPage";

const FAMILY = "10000000-0000-4000-8000-000000000001";
const CHILD = "20000000-0000-4000-8000-000000000001";

class DataCloud extends FakeCloud {
  readonly deleteCall = vi.fn(async (_profileId: string, _confirmation: string) => undefined);
  override deleteProfile(profileId: string, confirmation: string): Promise<void> {
    return this.deleteCall(profileId, confirmation);
  }
}

describe("DataControlsPage", () => {
  it("requires the exact nickname before destructive deletion", async () => {
    const cloud = new DataCloud({
      session: { status: "authenticated", userId: "00000000-0000-4000-8000-000000000001", role: "guardian" },
      families: [{ id: FAMILY, name: "모아 가족", role: "guardian" }],
      children: [{ id: CHILD, familyId: FAMILY, nickname: "서아", lastSyncAt: null }],
      dashboards: {},
    });
    render(
      <CloudProvider cloud={cloud}>
        <MemoryRouter><DataControlsPage /></MemoryRouter>
      </CloudProvider>,
    );

    await userEvent.click(await screen.findByRole("button", { name: "서아 데이터 삭제" }));
    const confirmation = screen.getByLabelText("확인을 위해 서아 입력");
    expect(screen.getByRole("button", { name: "영구 삭제" })).toBeDisabled();
    await userEvent.type(confirmation, "서아");
    await userEvent.click(screen.getByRole("button", { name: "영구 삭제" }));
    expect(cloud.deleteCall).toHaveBeenCalledWith(CHILD, "서아");
    expect(await screen.findByRole("status")).toHaveTextContent("삭제했습니다");
  });
});

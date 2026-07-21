import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { describe, expect, it } from "vitest";
import type { ContentDraft, SaveDraftInput } from "../cloud/cloud_port";

import { CloudProvider } from "../cloud/cloud_provider";
import { FakeCloud } from "../cloud/fake_cloud";
import { DraftEditorPage } from "./DraftEditorPage";
import { studioPackageFixture } from "./studio_test_fixture";

const DRAFT_ID = "30000000-0000-4000-8000-000000000001";

describe("DraftEditorPage", () => {
  it("edits difficulty/run values, validates, and saves with optimistic revision", async () => {
    const cloud = new FakeCloud({
      session: { status: "authenticated", userId: "00000000-0000-4000-8000-000000000001", role: "editor" },
      families: [], children: [], dashboards: {},
      drafts: [{ id: DRAFT_ID, activityId: "addition_ones", title: "덧셈 탐험", revision: 3, updatedAt: "2030-01-01T00:00:00.000Z", package: studioPackageFixture() }],
    });
    render(
      <CloudProvider cloud={cloud}>
        <MemoryRouter initialEntries={[`/studio/drafts/${DRAFT_ID}`]}>
          <Routes><Route path="/studio/drafts/:draftId" element={<DraftEditorPage />} /></Routes>
        </MemoryRouter>
      </CloudProvider>,
    );

    expect(await screen.findByRole("heading", { name: "덧셈 탐험 편집" })).toBeVisible();
    const target = screen.getByLabelText("완료 정답 수");
    await userEvent.clear(target);
    await userEvent.type(target, "12");
    await userEvent.click(screen.getByRole("button", { name: "초안 검증" }));
    expect(await screen.findByText("검증을 통과했습니다")).toBeVisible();
    await userEvent.click(screen.getByRole("button", { name: "초안 저장" }));
    expect(await screen.findByRole("status")).toHaveTextContent("revision 4");
  });

  it("loads and compares the latest revision instead of silently overwriting a conflict", async () => {
    const original = studioPackageFixture();
    const remote = structuredClone(original);
    remote.run.goal.target = 20;
    class ConflictCloud extends FakeCloud {
      loads = 0;
      override async loadDraft() {
        this.loads += 1;
        return {
          id: DRAFT_ID,
          activityId: "addition_ones" as const,
          title: "덧셈 탐험",
          revision: this.loads === 1 ? 3 : 4,
          updatedAt: "2030-01-01T00:00:00.000Z",
          package: structuredClone(this.loads === 1 ? original : remote),
        };
      }
      override async saveDraft(_input: SaveDraftInput): Promise<ContentDraft> {
        throw new Error("Draft revision conflict");
      }
    }
    const cloud = new ConflictCloud({
      session: { status: "authenticated", userId: "00000000-0000-4000-8000-000000000001", role: "editor" },
      families: [], children: [], dashboards: {}, drafts: [],
    });
    render(
      <CloudProvider cloud={cloud}>
        <MemoryRouter initialEntries={[`/studio/drafts/${DRAFT_ID}`]}>
          <Routes><Route path="/studio/drafts/:draftId" element={<DraftEditorPage />} /></Routes>
        </MemoryRouter>
      </CloudProvider>,
    );

    const target = await screen.findByLabelText("완료 정답 수");
    await userEvent.clear(target);
    await userEvent.type(target, "12");
    await userEvent.click(screen.getByRole("button", { name: "초안 저장" }));

    expect(await screen.findByRole("heading", { name: "동시 편집 충돌" })).toBeVisible();
    expect(screen.getByText(/서버 revision 4/)).toBeVisible();
    expect(screen.getByText("/run/goal/target", { selector: "code" })).toBeVisible();
    await userEvent.click(screen.getByRole("button", { name: "서버 최신본 열기" }));
    expect(screen.getByLabelText("완료 정답 수")).toHaveValue(20);
  });
});

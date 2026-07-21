import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";

import type { ContentDraft } from "../cloud/cloud_port";
import { AiDraftPanel } from "./AiDraftPanel";
import { studioPackageFixture } from "./studio_test_fixture";

describe("AiDraftPanel", () => {
  it("shows a reviewable diff and applies only to the local draft after confirmation", async () => {
    const draft = studioPackageFixture();
    const onApply = vi.fn<(next: ContentDraft["package"]) => void>();
    const request = vi.fn(async () => ({
      draftId: "30000000-0000-4000-8000-000000000001",
      baseRevision: 3,
      provider: "configured-test",
      patch: [{ op: "replace" as const, path: "/run/goal/target", value: 14 }],
    }));

    render(<AiDraftPanel draft={draft} request={request} onApply={onApply} />);
    await userEvent.type(screen.getByLabelText("바꾸고 싶은 내용"), "목표를 14개로 바꿔 줘");
    await userEvent.click(screen.getByRole("button", { name: "검토용 제안 만들기" }));

    expect(await screen.findByText("/run/goal/target")).toBeVisible();
    expect(screen.getByText("10 → 14")).toBeVisible();
    expect(onApply).not.toHaveBeenCalled();

    await userEvent.click(screen.getByRole("button", { name: "이 초안에 적용" }));
    expect(onApply).toHaveBeenCalledOnce();
    expect(onApply.mock.calls[0]![0].run.goal.target).toBe(14);
    expect(await screen.findByRole("status")).toHaveTextContent("미저장 초안에만 반영");
  });

  it("keeps manual editing available when no provider is configured", async () => {
    render(
      <AiDraftPanel
        draft={studioPackageFixture()}
        request={async () => ({
          draftId: "30000000-0000-4000-8000-000000000001",
          baseRevision: 3,
          provider: "fake-disabled",
          patch: [],
        })}
        onApply={() => undefined}
      />,
    );
    await userEvent.type(screen.getByLabelText("바꾸고 싶은 내용"), "조금 쉽게");
    await userEvent.click(screen.getByRole("button", { name: "검토용 제안 만들기" }));
    expect(await screen.findByRole("status")).toHaveTextContent("수동 편집은 계속 사용할 수");
    expect(screen.queryByRole("button", { name: "이 초안에 적용" })).not.toBeInTheDocument();
  });
});

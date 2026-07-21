import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";

import type { ContentDraft, ContentPublicationHistoryItem, ValidationReportWire } from "../cloud/cloud_port";
import { CloudProvider } from "../cloud/cloud_provider";
import { FakeCloud } from "../cloud/fake_cloud";
import { HistoryPage } from "./HistoryPage";
import { PublishDialog } from "./PublishDialog";
import { studioPackageFixture } from "./studio_test_fixture";

const DRAFT_ID = "30000000-0000-4000-8000-000000000001";
const OWNER_ID = "00000000-0000-4000-8000-000000000001";

function draft(): ContentDraft {
  return {
    id: DRAFT_ID,
    activityId: "addition_ones",
    title: "덧셈 탐험",
    revision: 3,
    updatedAt: "2030-01-01T00:00:00.000Z",
    package: studioPackageFixture(),
  };
}

const validReport: ValidationReportWire = { valid: true, issues: [], samples: [{ seed: 1 }] };

function fake(publications: ContentPublicationHistoryItem[] = []) {
  return new FakeCloud({
    session: { status: "authenticated", userId: OWNER_ID, role: "owner" },
    families: [], children: [], dashboards: {}, drafts: [draft()], publications,
  });
}

describe("content publication", () => {
  it("requires validation, reason, and exact version confirmation before publishing", async () => {
    const onPublished = vi.fn();
    render(
      <CloudProvider cloud={fake()}>
        <PublishDialog draft={draft()} report={validReport} onClose={() => undefined} onPublished={onPublished} />
      </CloudProvider>,
    );

    expect(screen.getByText("검증 통과 · 샘플 1개")).toBeVisible();
    expect(screen.getByRole("button", { name: "지금 배포" })).toBeDisabled();
    await userEvent.type(screen.getByLabelText("배포 이유"), "현장 범위 조정");
    await userEvent.type(screen.getByLabelText("버전 확인"), "1.0.0");
    await userEvent.click(screen.getByRole("button", { name: "지금 배포" }));

    expect(onPublished).toHaveBeenCalledOnce();
    expect(onPublished.mock.calls[0]![0].package.checksum).toMatch(/^sha256:[0-9a-f]{64}$/);
  });

  it("keeps invalid drafts blocked", () => {
    render(
      <CloudProvider cloud={fake()}>
        <PublishDialog
          draft={draft()}
          report={{ valid: false, issues: [{ code: "BAD", path: ["run"], message: "수정 필요" }], samples: [] }}
          onClose={() => undefined}
          onPublished={() => undefined}
        />
      </CloudProvider>,
    );
    expect(screen.getByRole("button", { name: "지금 배포" })).toBeDisabled();
    expect(screen.getByRole("alert")).toHaveTextContent("검증을 통과한 저장본만");
  });

  it("shows immutable history and rolls back only after explicit confirmation", async () => {
    const checksum = `sha256:${"1".repeat(64)}`;
    const publications: ContentPublicationHistoryItem[] = [
      { id: "40000000-0000-4000-8000-000000000001", activityId: "addition_ones", contentVersion: "1.0.0", checksum, status: "retired", publishedAt: "2029-12-01T00:00:00.000Z", effectiveAt: "2029-12-01T00:00:00.000Z", publishedBy: OWNER_ID, sourceRevision: 1, rollbackOfId: null, reason: "첫 배포", validationValid: true },
      { id: "40000000-0000-4000-8000-000000000002", activityId: "addition_ones", contentVersion: "2.0.0", checksum: `sha256:${"2".repeat(64)}`, status: "active", publishedAt: "2029-12-02T00:00:00.000Z", effectiveAt: "2029-12-02T00:00:00.000Z", publishedBy: OWNER_ID, sourceRevision: 2, rollbackOfId: null, reason: "범위 확대", validationValid: true },
    ];
    render(<CloudProvider cloud={fake(publications)}><HistoryPage /></CloudProvider>);

    expect(await screen.findByText("활성", { selector: ".status-badge" })).toBeVisible();
    await userEvent.click(screen.getByRole("button", { name: "1.0.0 롤백" }));
    expect(screen.getByRole("heading", { name: "이전 버전으로 롤백" })).toBeVisible();
    await userEvent.type(screen.getByLabelText("롤백 이유"), "수업 난이도 복원");
    await userEvent.type(screen.getByLabelText("버전 확인"), "1.0.0");
    await userEvent.click(screen.getByRole("button", { name: "롤백 실행" }));
    expect(await screen.findByRole("status")).toHaveTextContent("1.0.0 버전으로 롤백");
  });
});

import { useState } from "react";
import { ActivityPackageDraftV1Schema } from "@mathland/contracts/content/schema";
import type { AiPatchResult } from "../cloud/cloud_port";
import type { ContentDraft } from "../cloud/cloud_port";
import { applyJsonPatch } from "./ai_patch";
import { diffDraft, type DraftChange } from "./draft_diff";

export interface AiDraftPanelProps {
  draft: ContentDraft["package"];
  request(instruction: string): Promise<AiPatchResult>;
  onApply(next: ContentDraft["package"]): void;
}

type Review = {
  result: AiPatchResult;
  candidate: ContentDraft["package"];
  changes: DraftChange[];
};

function displayValue(value: unknown): string {
  if (value === undefined) return "(없음)";
  const encoded = JSON.stringify(value);
  return encoded.length > 80 ? `${encoded.slice(0, 77)}…` : encoded;
}

export function AiDraftPanel({ draft, request, onApply }: AiDraftPanelProps) {
  const [instruction, setInstruction] = useState("");
  const [review, setReview] = useState<Review | null>(null);
  const [pending, setPending] = useState(false);
  const [message, setMessage] = useState("");

  async function ask() {
    if (!instruction.trim()) return;
    setPending(true);
    setMessage("");
    try {
      const next = await request(instruction.trim());
      if (next.provider === "fake-disabled") {
        setReview(null);
        setMessage("AI 제공자가 설정되지 않았습니다. 수동 편집은 계속 사용할 수 있습니다.");
        return;
      }
      const patched = applyJsonPatch(draft, next.patch);
      const parsed = ActivityPackageDraftV1Schema.safeParse(patched);
      if (!parsed.success) {
        setReview(null);
        setMessage("제안이 콘텐츠 규칙을 통과하지 못해 적용할 수 없습니다.");
        return;
      }
      setReview({ result: next, candidate: parsed.data, changes: diffDraft(draft, parsed.data) });
      setMessage("검토할 변경안을 받았습니다. 자동 저장이나 배포는 하지 않습니다.");
    } catch {
      setReview(null);
      setMessage("AI 제안을 만들지 못했습니다. 수동 편집 내용은 그대로 보존됩니다.");
    } finally {
      setPending(false);
    }
  }

  function apply() {
    if (!review) return;
    onApply(review.candidate);
    setReview(null);
    setMessage("변경안을 미저장 초안에만 반영했습니다. 검증 후 직접 저장해 주세요.");
  }

  return (
    <section className="studio-section ai-panel">
      <h2>AI로 난이도 초안 제안받기 <span>선택 기능</span></h2>
      <p>선택한 초안만 전송하며 아이의 답안·학습 기록은 보내지 않습니다. 제안은 저장 전에 사람이 검토합니다.</p>
      <label>바꾸고 싶은 내용
        <textarea value={instruction} onChange={(event) => setInstruction(event.currentTarget.value)} placeholder="예: 연습 단계 덧셈 범위를 20까지로 넓혀 줘" />
      </label>
      <button type="button" disabled={pending || !instruction.trim()} onClick={() => void ask()}>{pending ? "제안 만드는 중…" : "검토용 제안 만들기"}</button>
      {message ? <p role="status">{message}</p> : null}
      {review ? (
        <div className="ai-review">
          <h3>변경안 {review.changes.length}개</h3>
          <ol className="ai-diff">
            {review.changes.map((change) => (
              <li key={change.path}>
                <code>{change.path}</code>
                <span>{displayValue(change.before)} → {displayValue(change.after)}</span>
              </li>
            ))}
          </ol>
          <p className="fine-print">제공자: {review.result.provider} · 아직 저장되지 않음</p>
          <div className="dialog-actions">
            <button type="button" onClick={() => { setReview(null); setMessage("변경안을 폐기했습니다. 기존 초안은 그대로입니다."); }}>폐기</button>
            <button type="button" onClick={apply}>이 초안에 적용</button>
          </div>
        </div>
      ) : null}
    </section>
  );
}

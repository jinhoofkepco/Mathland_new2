import { useState } from "react";

import type { ContentDraft, ContentPublication, ValidationReportWire } from "../cloud/cloud_port";
import { useCloud } from "../cloud/cloud_provider";

export function PublishDialog({
  draft,
  report,
  onClose,
  onPublished,
}: {
  draft: ContentDraft;
  report: ValidationReportWire | null;
  onClose(): void;
  onPublished(publication: ContentPublication): void;
}) {
  const cloud = useCloud();
  const [reason, setReason] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const [scheduled, setScheduled] = useState(false);
  const [effectiveAt, setEffectiveAt] = useState("");
  const [pending, setPending] = useState(false);
  const [error, setError] = useState("");
  const version = draft.package.content_version;
  const scheduleValid = !scheduled || (effectiveAt !== "" && new Date(effectiveAt).getTime() > Date.now());
  const ready = report?.valid === true && reason.trim() !== "" && confirmation === version && scheduleValid;

  async function publish() {
    if (!ready) return;
    setPending(true);
    setError("");
    try {
      const publication = await cloud.publishDraft(draft.id, draft.revision, {
        reason: reason.trim(),
        ...(scheduled ? { effectiveAt: new Date(effectiveAt).toISOString() } : {}),
      });
      onPublished(publication);
    } catch {
      setError("배포하지 못했습니다. 권한, 최신 revision, 검증 결과를 확인해 주세요.");
    } finally {
      setPending(false);
    }
  }

  return (
    <div className="dialog-backdrop" role="presentation">
      <section className="dialog-card publish-dialog" role="dialog" aria-modal="true" aria-labelledby="publish-title">
        <p className="eyebrow">불변 콘텐츠 버전 만들기</p>
        <h2 id="publish-title">{version} 배포</h2>
        {report?.valid ? (
          <p className="validation-summary">검증 통과 · 샘플 {report.samples.length}개</p>
        ) : (
          <p role="alert">검증을 통과한 저장본만 배포할 수 있습니다.</p>
        )}
        <dl className="publication-summary">
          <div><dt>활동</dt><dd>{draft.activityId}</dd></div>
          <div><dt>revision</dt><dd>{draft.revision}</dd></div>
          <div><dt>체력</dt><dd>{draft.package.run.starting_hearts} · 오답 시 감소</dd></div>
          <div><dt>난이도</dt><dd>{draft.package.difficulty_bands.map((band) => band.band_id).join(" → ")}</dd></div>
        </dl>
        <label>배포 이유
          <textarea value={reason} maxLength={500} onChange={(event) => setReason(event.currentTarget.value)} placeholder="예: 2학기 수업 범위에 맞춰 challenge 범위를 조정" />
        </label>
        <label className="checkbox-label"><input type="checkbox" checked={scheduled} onChange={(event) => setScheduled(event.currentTarget.checked)} />예약 배포</label>
        {scheduled ? <label>적용 시각
          <input type="datetime-local" value={effectiveAt} onChange={(event) => setEffectiveAt(event.currentTarget.value)} />
          {!scheduleValid ? <small role="alert">현재보다 뒤의 시각을 선택해 주세요.</small> : null}
        </label> : <p className="fine-print">확인 즉시 현재 활성 버전이 교체됩니다.</p>}
        <label>버전 확인
          <input aria-label="버전 확인" value={confirmation} onChange={(event) => setConfirmation(event.currentTarget.value)} autoComplete="off" placeholder={version} />
          <small>실수를 막기 위해 <strong>{version}</strong>을 그대로 입력하세요.</small>
        </label>
        {error ? <p role="alert">{error}</p> : null}
        <div className="dialog-actions">
          <button type="button" disabled={pending} onClick={onClose}>취소</button>
          <button type="button" disabled={pending || !ready} onClick={() => void publish()}>{scheduled ? "예약 배포" : "지금 배포"}</button>
        </div>
      </section>
    </div>
  );
}

import { useState } from "react";

import type { ContentPublication, ContentPublicationHistoryItem } from "../cloud/cloud_port";
import { useCloud } from "../cloud/cloud_provider";

export function RollbackDialog({
  publication,
  onClose,
  onRolledBack,
}: {
  publication: ContentPublicationHistoryItem;
  onClose(): void;
  onRolledBack(result: ContentPublication): void;
}) {
  const cloud = useCloud();
  const [reason, setReason] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const [pending, setPending] = useState(false);
  const [error, setError] = useState("");
  const ready = publication.status === "retired" && publication.validationValid && reason.trim() !== "" && confirmation === publication.contentVersion;

  async function rollback() {
    if (!ready) return;
    setPending(true);
    setError("");
    try {
      onRolledBack(await cloud.rollbackPublication(publication.id, reason.trim()));
    } catch {
      setError("롤백하지 못했습니다. 과거 검증본과 현재 권한을 확인해 주세요.");
    } finally {
      setPending(false);
    }
  }

  return (
    <div className="dialog-backdrop" role="presentation">
      <section className="dialog-card" role="dialog" aria-modal="true" aria-labelledby="rollback-title">
        <p className="eyebrow">새 이력으로 남는 복원 작업</p>
        <h2 id="rollback-title">이전 버전으로 롤백</h2>
        <p><strong>{publication.activityId} {publication.contentVersion}</strong>의 불변 패키지를 다시 활성화합니다. 기존 이력은 삭제되지 않습니다.</p>
        <label>롤백 이유<textarea maxLength={500} value={reason} onChange={(event) => setReason(event.currentTarget.value)} /></label>
        <label>버전 확인
          <input autoComplete="off" value={confirmation} placeholder={publication.contentVersion} onChange={(event) => setConfirmation(event.currentTarget.value)} />
        </label>
        {error ? <p role="alert">{error}</p> : null}
        <div className="dialog-actions">
          <button type="button" disabled={pending} onClick={onClose}>취소</button>
          <button className="danger-button" type="button" disabled={pending || !ready} onClick={() => void rollback()}>롤백 실행</button>
        </div>
      </section>
    </div>
  );
}

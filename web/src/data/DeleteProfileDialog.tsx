import { type FormEvent, useState } from "react";

import type { ChildSummary } from "../cloud/cloud_port";

export interface DeleteProfileDialogProps {
  child: ChildSummary;
  pending: boolean;
  onCancel(): void;
  onConfirm(value: string): Promise<void>;
}

export function DeleteProfileDialog({ child, pending, onCancel, onConfirm }: DeleteProfileDialogProps) {
  const [confirmation, setConfirmation] = useState("");
  async function submit(event: FormEvent) {
    event.preventDefault();
    if (confirmation === child.nickname) await onConfirm(confirmation);
  }
  return (
    <div className="dialog-backdrop" role="presentation">
      <section className="dialog-card danger-card" role="dialog" aria-modal="true" aria-labelledby="delete-title">
        <h2 id="delete-title">{child.nickname} 데이터 영구 삭제</h2>
        <p>학습 기록, 보상, 연결 정보가 삭제됩니다. 이 작업은 되돌릴 수 없습니다.</p>
        <form onSubmit={(event) => void submit(event)}>
          <label htmlFor="delete-confirmation">확인을 위해 {child.nickname} 입력</label>
          <input
            id="delete-confirmation"
            value={confirmation}
            onChange={(event) => setConfirmation(event.currentTarget.value)}
            autoComplete="off"
            disabled={pending}
          />
          <div className="dialog-actions">
            <button type="button" onClick={onCancel} disabled={pending}>취소</button>
            <button className="danger-button" type="submit" disabled={pending || confirmation !== child.nickname}>영구 삭제</button>
          </div>
        </form>
      </section>
    </div>
  );
}

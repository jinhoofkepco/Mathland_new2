import type { PairingCodeResult } from "../cloud/cloud_port";

export interface PairingCodeDialogProps {
  childName: string;
  result: PairingCodeResult;
  onClose(): void;
}

export function PairingCodeDialog({ childName, result, onClose }: PairingCodeDialogProps) {
  const displayCode = `${result.code.slice(0, 3)} ${result.code.slice(3)}`;
  return (
    <div className="dialog-backdrop" role="presentation">
      <section className="dialog-card" role="dialog" aria-modal="true" aria-labelledby="pair-title">
        <p className="eyebrow">한 번만 사용할 수 있어요</p>
        <h2 id="pair-title">{childName} 기기 연결</h2>
        <output className="pairing-code" aria-label={`연결 코드 ${result.code}`}>{displayCode}</output>
        <p>10분 안에 아이 기기의 연결 화면에 입력해 주세요.</p>
        <p className="fine-print">만료: {new Intl.DateTimeFormat("ko-KR", { timeStyle: "short" }).format(new Date(result.expiresAt))}</p>
        <button className="primary-action button-reset" type="button" onClick={onClose}>연결 코드 닫기</button>
      </section>
    </div>
  );
}

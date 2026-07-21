import { useCallback, useEffect, useMemo, useState } from "react";

import type { ContentPublication, ContentPublicationHistoryItem } from "../cloud/cloud_port";
import { useCloud } from "../cloud/cloud_provider";
import { RollbackDialog } from "./RollbackDialog";

const STATUS_LABELS: Record<ContentPublicationHistoryItem["status"], string> = {
  active: "활성",
  pending: "예약",
  retired: "이전",
};

function displayDate(value: string): string {
  return new Intl.DateTimeFormat("ko-KR", { dateStyle: "medium", timeStyle: "short" }).format(new Date(value));
}

export function HistoryPage() {
  const cloud = useCloud();
  const [items, setItems] = useState<ContentPublicationHistoryItem[]>([]);
  const [activity, setActivity] = useState("all");
  const [rollback, setRollback] = useState<ContentPublicationHistoryItem | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [message, setMessage] = useState("");

  const load = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      setItems(await cloud.listPublicationHistory());
    } catch {
      setError("배포 이력을 불러오지 못했습니다.");
    } finally {
      setLoading(false);
    }
  }, [cloud]);

  useEffect(() => { void load(); }, [load]);
  const activities = useMemo(() => [...new Set(items.map((item) => item.activityId))].sort(), [items]);
  const visible = activity === "all" ? items : items.filter((item) => item.activityId === activity);

  function rolledBack(result: ContentPublication) {
    setRollback(null);
    setMessage(`${result.activityId}을 ${result.contentVersion} 버전으로 롤백했습니다.`);
    void load();
  }

  return (
    <main id="main-content" className="management-page history-page">
      <p className="eyebrow">삭제되지 않는 변경 기록</p>
      <div className="page-heading"><div><h1>콘텐츠 배포 이력</h1><p>예약·활성·이전 버전과 롤백 연결을 확인합니다.</p></div>
        <label>활동 필터
          <select value={activity} onChange={(event) => setActivity(event.currentTarget.value)}><option value="all">전체</option>{activities.map((id) => <option key={id}>{id}</option>)}</select>
        </label>
      </div>
      {loading ? <p aria-busy="true">이력을 불러오는 중…</p> : null}
      {error ? <p role="alert">{error}</p> : null}
      {message ? <p role="status">{message}</p> : null}
      <section className="history-list" aria-label="배포 이력">
        {visible.map((item) => (
          <article key={item.id}>
            <header><div><span className={`status-badge is-${item.status}`}>{STATUS_LABELS[item.status]}</span><h2>{item.activityId} · {item.contentVersion}</h2></div>
              {item.status === "retired" && item.validationValid ? <button type="button" onClick={() => setRollback(item)}>{item.contentVersion} 롤백</button> : null}
            </header>
            <dl className="publication-summary">
              <div><dt>적용</dt><dd><time dateTime={item.effectiveAt}>{displayDate(item.effectiveAt)}</time></dd></div>
              <div><dt>원본 revision</dt><dd>{item.sourceRevision}</dd></div>
              <div><dt>검증</dt><dd>{item.validationValid ? "통과" : "실패"}</dd></div>
              <div><dt>작업자</dt><dd>{item.publishedBy ? item.publishedBy.slice(0, 8) : "삭제된 계정"}</dd></div>
            </dl>
            <p>{item.reason ?? "이유 기록 없음"}</p>
            <code className="checksum">{item.checksum}</code>
            {item.rollbackOfId ? <p className="fine-print">롤백 원본: {item.rollbackOfId}</p> : null}
          </article>
        ))}
        {!loading && visible.length === 0 ? <p>표시할 배포 이력이 없습니다.</p> : null}
      </section>
      {rollback ? <RollbackDialog publication={rollback} onClose={() => setRollback(null)} onRolledBack={rolledBack} /> : null}
    </main>
  );
}

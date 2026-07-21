import { useEffect, useState } from "react";
import { Link } from "react-router-dom";

import type { ContentDraftSummary } from "../cloud/cloud_port";
import { useCloud } from "../cloud/cloud_provider";

export function StudioPage() {
  const cloud = useCloud();
  const [drafts, setDrafts] = useState<ContentDraftSummary[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  useEffect(() => {
    let current = true;
    void cloud.listDrafts().then(
      (rows) => {
        if (current) setDrafts(rows);
      },
      () => current && setError("콘텐츠 초안을 불러오지 못했습니다."),
    ).finally(() => current && setLoading(false));
    return () => {
      current = false;
    };
  }, [cloud]);

  return (
    <main id="main-content" className="management-page studio-page">
      <p className="eyebrow">배포 전 검증되는 현장 조절 도구</p>
      <h1>콘텐츠 스튜디오</h1>
      <p>게임 코드를 다시 빌드하지 않고 난이도·보상·시간·문구를 초안으로 조정합니다.</p>
      {loading ? <p aria-busy="true">초안을 불러오는 중…</p> : null}
      {error ? <p role="alert">{error}</p> : null}
      <section className="management-list" aria-label="콘텐츠 초안">
        {drafts.map((draft) => (
          <article key={draft.id}>
            <div><h2>{draft.title}</h2><p>{draft.activityId} · revision {draft.revision}</p></div>
            <Link className="studio-link" to={`/studio/drafts/${draft.id}`}>편집하기</Link>
          </article>
        ))}
        {!loading && drafts.length === 0 ? <p>아직 저장된 초안이 없습니다.</p> : null}
      </section>
    </main>
  );
}

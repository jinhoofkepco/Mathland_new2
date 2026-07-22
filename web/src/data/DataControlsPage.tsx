import { useEffect, useState } from "react";

import type { ChildSummary, FamilySummary } from "../cloud/cloud_port";
import { useCloud } from "../cloud/cloud_provider";
import { DeleteProfileDialog } from "./DeleteProfileDialog";

function downloadBlob(blob: Blob, filename: string) {
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  link.click();
  URL.revokeObjectURL(url);
}

export function DataControlsPage() {
  const cloud = useCloud();
  const [families, setFamilies] = useState<FamilySummary[]>([]);
  const [children, setChildren] = useState<ChildSummary[]>([]);
  const [deleting, setDeleting] = useState<ChildSummary | null>(null);
  const [pending, setPending] = useState(false);
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");

  useEffect(() => {
    let current = true;
    void cloud.listFamilies().then(async (familyRows) => {
      const childRows = await Promise.all(familyRows.map((family) => cloud.listChildren(family.id)));
      if (!current) return;
      setFamilies(familyRows);
      setChildren(childRows.flat());
    }).catch(() => current && setError("데이터 목록을 불러오지 못했습니다."));
    return () => {
      current = false;
    };
  }, [cloud]);

  async function exportFamily(family: FamilySummary) {
    setError("");
    try {
      const blob = await cloud.exportFamily(family.id);
      downloadBlob(blob, `mathland-${family.id}-export.json`);
      setMessage("가족 데이터 파일을 내려받았습니다.");
    } catch {
      setError("가족 데이터를 내보내지 못했습니다.");
    }
  }

  async function removeProfile(confirmation: string) {
    if (!deleting) return;
    setPending(true);
    setError("");
    try {
      await cloud.deleteProfile(deleting.id, confirmation);
      setChildren((rows) => rows.filter((child) => child.id !== deleting.id));
      setDeleting(null);
      setMessage(`${deleting.nickname} 프로필과 연결된 데이터를 삭제했습니다.`);
    } catch {
      setError("삭제하지 못했습니다. 입력한 이름과 권한을 확인해 주세요.");
    } finally {
      setPending(false);
    }
  }

  return (
    <main id="main-content" className="management-page">
      <p className="eyebrow">내보내기와 삭제를 직접 관리</p>
      <h1>데이터 관리</h1>
      <p>가족 데이터 사본을 내려받거나 자녀 프로필을 영구 삭제할 수 있습니다.</p>
      {message ? <p role="status">{message}</p> : null}
      {error ? <p role="alert">{error}</p> : null}
      <section className="management-list" aria-label="가족 데이터 내보내기">
        {families.map((family) => (
          <article key={family.id}>
            <div><h2>{family.name}</h2><p>JSON 형식의 전체 가족 데이터 사본</p></div>
            <button type="button" onClick={() => void exportFamily(family)}>데이터 내보내기</button>
          </article>
        ))}
      </section>
      <section className="management-list danger-zone" aria-labelledby="danger-heading">
        <h2 id="danger-heading">자녀 데이터 삭제</h2>
        {children.map((child) => (
          <article key={child.id}>
            <div><h3>{child.nickname}</h3><p>학습·보상·기기 연결을 모두 삭제</p></div>
            <button className="danger-button" type="button" onClick={() => setDeleting(child)}>{child.nickname} 데이터 삭제</button>
          </article>
        ))}
      </section>
      {deleting ? (
        <DeleteProfileDialog
          child={deleting}
          pending={pending}
          onCancel={() => setDeleting(null)}
          onConfirm={removeProfile}
        />
      ) : null}
    </main>
  );
}

import { useEffect, useState } from "react";

import type { ChildSummary, PairingCodeResult } from "../cloud/cloud_port";
import { useCloud } from "../cloud/cloud_provider";
import { PairingCodeDialog } from "./PairingCodeDialog";

export function DevicesPage() {
  const cloud = useCloud();
  const [children, setChildren] = useState<ChildSummary[]>([]);
  const [pairing, setPairing] = useState<{ child: ChildSummary; result: PairingCodeResult } | null>(null);
  const [error, setError] = useState("");

  useEffect(() => {
    let current = true;
    void cloud.listFamilies().then(async (families) => {
      const rows = await Promise.all(families.map((family) => cloud.listChildren(family.id)));
      if (current) setChildren(rows.flat());
    }).catch(() => current && setError("기기 연결 정보를 불러오지 못했습니다."));
    return () => {
      current = false;
    };
  }, [cloud]);

  async function createCode(child: ChildSummary) {
    setError("");
    try {
      setPairing({ child, result: await cloud.createPairingCode(child.id) });
    } catch {
      setError("연결 코드를 만들지 못했습니다.");
    }
  }

  return (
    <main id="main-content" className="management-page">
      <p className="eyebrow">아이 휴대폰과 안전하게 연결</p>
      <h1>기기 연결</h1>
      <p>코드는 서버에 원문으로 저장되지 않으며 10분 뒤 만료됩니다.</p>
      {error ? <p role="alert">{error}</p> : null}
      <section className="management-list" aria-label="자녀 프로필">
        {children.map((child) => (
          <article key={child.id}>
            <div><h2>{child.nickname}</h2><p>{child.lastSyncAt ? "연결된 기록 있음" : "아직 연결되지 않음"}</p></div>
            <button type="button" onClick={() => void createCode(child)}>{child.nickname} 기기 연결</button>
          </article>
        ))}
      </section>
      {pairing ? (
        <PairingCodeDialog
          childName={pairing.child.nickname}
          result={pairing.result}
          onClose={() => setPairing(null)}
        />
      ) : null}
    </main>
  );
}

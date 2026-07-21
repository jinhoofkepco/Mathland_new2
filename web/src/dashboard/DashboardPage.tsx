import { useEffect, useMemo, useState } from "react";

import type {
  ChildSummary,
  DashboardRange,
  DashboardSnapshot,
  FamilySummary,
} from "../cloud/cloud_port";
import { useCloud } from "../cloud/cloud_provider";

const RANGE_LABELS: Record<DashboardRange, string> = {
  "7d": "최근 7일",
  "30d": "최근 30일",
  "90d": "최근 90일",
};

const BAND_LABELS: Record<string, string> = {
  intro: "첫걸음",
  practice: "연습",
  challenge: "도전",
};

function formatSync(timestamp: string | null): string {
  if (!timestamp) return "아직 동기화되지 않음";
  return new Intl.DateTimeFormat("ko-KR", { dateStyle: "medium", timeStyle: "short" }).format(
    new Date(timestamp),
  );
}

export function DashboardPage() {
  const cloud = useCloud();
  const [families, setFamilies] = useState<FamilySummary[]>([]);
  const [familyId, setFamilyId] = useState<string>("");
  const [children, setChildren] = useState<ChildSummary[]>([]);
  const [profileId, setProfileId] = useState<string>("");
  const [range, setRange] = useState<DashboardRange>("7d");
  const [snapshot, setSnapshot] = useState<DashboardSnapshot | null>(null);
  const [error, setError] = useState("");

  useEffect(() => {
    let current = true;
    void cloud.listFamilies().then(
      (rows) => {
        if (!current) return;
        setFamilies(rows);
        setFamilyId((selected) => selected || rows[0]?.id || "");
      },
      () => current && setError("가족 정보를 불러오지 못했습니다."),
    );
    return () => {
      current = false;
    };
  }, [cloud]);

  useEffect(() => {
    if (!familyId) return;
    let current = true;
    setSnapshot(null);
    void cloud.listChildren(familyId).then(
      (rows) => {
        if (!current) return;
        setChildren(rows);
        setProfileId((selected) =>
          rows.some((child) => child.id === selected) ? selected : rows[0]?.id || "",
        );
      },
      () => current && setError("자녀 프로필을 불러오지 못했습니다."),
    );
    return () => {
      current = false;
    };
  }, [cloud, familyId]);

  useEffect(() => {
    if (!familyId || !profileId) return;
    let current = true;
    setSnapshot(null);
    setError("");
    void cloud.dashboard({ familyId, profileId, range }).then(
      (value) => current && setSnapshot(value),
      () => current && setError("학습 현황을 불러오지 못했습니다."),
    );
    return () => {
      current = false;
    };
  }, [cloud, familyId, profileId, range]);

  const selectedChild = children.find((child) => child.id === profileId) ?? null;
  const stats = useMemo(() => {
    if (!snapshot) return null;
    const answers = snapshot.activities.reduce((total, row) => total + row.answerCount, 0);
    const correct = snapshot.activities.reduce((total, row) => total + row.correctCount, 0);
    const weightedDuration = snapshot.activities.reduce(
      (total, row) => total + row.averageResponseDurationMs * row.answerCount,
      0,
    );
    const apples = snapshot.rewards
      .filter((reward) => reward.rewardId === "apple")
      .reduce((total, reward) => total + reward.quantity, 0);
    return {
      answers,
      accuracy: answers === 0 ? 0 : Math.round((correct / answers) * 100),
      averageSeconds: answers === 0 ? 0 : weightedDuration / answers / 1000,
      apples,
    };
  }, [snapshot]);

  if (error) return <main id="main-content" className="state-page" role="alert">{error}</main>;
  if (families.length === 0 && familyId === "") {
    return <main id="main-content" className="state-page" aria-busy="true">가족 탐험 기록을 불러오는 중…</main>;
  }
  if (children.length === 0) {
    return (
      <main id="main-content" className="dashboard-page">
        <h1>연결된 자녀 프로필이 없습니다</h1>
        <p>아이 기기에서 프로필을 만든 뒤 기기 연결 메뉴에서 연결해 주세요.</p>
      </main>
    );
  }

  return (
    <main id="main-content" className="dashboard-page">
      <header className="page-heading">
        <div>
          <p className="eyebrow">멀리서도 가볍게 확인하세요</p>
          <h1>{selectedChild?.nickname ?? "아이"}의 탐험 현황</h1>
          <p>마지막 동기화: {formatSync(selectedChild?.lastSyncAt ?? null)}</p>
        </div>
        {families.length > 1 ? (
          <label>가족
            <select value={familyId} onChange={(event) => setFamilyId(event.currentTarget.value)}>
              {families.map((family) => <option key={family.id} value={family.id}>{family.name}</option>)}
            </select>
          </label>
        ) : null}
      </header>

      <div className="filter-row" aria-label="자녀 선택">
        {children.map((child) => (
          <button
            key={child.id}
            type="button"
            aria-pressed={profileId === child.id}
            onClick={() => setProfileId(child.id)}
          >
            {child.nickname}
          </button>
        ))}
      </div>
      <div className="filter-row" aria-label="조회 기간">
        {(Object.keys(RANGE_LABELS) as DashboardRange[]).map((value) => (
          <button
            key={value}
            type="button"
            aria-pressed={range === value}
            onClick={() => setRange(value)}
          >
            {RANGE_LABELS[value]}
          </button>
        ))}
      </div>

      {!snapshot || !stats ? (
        <p className="loading-card" aria-busy="true">기록을 정리하는 중…</p>
      ) : (
        <>
          <section className="stat-grid" aria-label="학습 요약">
            <article><span>플레이</span><strong>{snapshot.sessions.length}회</strong></article>
            <article><span>정답률</span><strong>{stats.accuracy}%</strong></article>
            <article><span>문제 속도</span><strong>평균 {stats.averageSeconds.toFixed(1)}초</strong></article>
            <article><span>모은 보상</span><strong>사과 {stats.apples}개</strong></article>
          </section>
          <section className="dashboard-panel" aria-labelledby="activity-heading">
            <h2 id="activity-heading">활동별 흐름</h2>
            {snapshot.activities.length === 0 ? <p>이 기간에는 아직 플레이 기록이 없습니다.</p> : (
              <ul className="activity-list">
                {snapshot.activities.map((activity) => (
                  <li key={`${activity.profileId}-${activity.activityId}`}>
                    <strong>{activity.activityId}</strong>
                    <span>{activity.correctCount}/{activity.answerCount} 정답</span>
                  </li>
                ))}
              </ul>
            )}
          </section>
          <section className="dashboard-panel" aria-labelledby="errors-heading">
            <h2 id="errors-heading">다시 보면 좋은 부분</h2>
            {snapshot.errors.length === 0 ? <p>반복해서 어려워한 유형이 없습니다.</p> : (
              <ul className="activity-list">
                {snapshot.errors.map((pattern) => (
                  <li key={`${pattern.activityId}-${pattern.generatorId}-${pattern.bandId}`}>
                    <strong>{pattern.activityId}</strong>
                    <span>{BAND_LABELS[pattern.bandId] ?? pattern.bandId} 단계에서 {pattern.incorrectCount}번 어려워했어요</span>
                  </li>
                ))}
              </ul>
            )}
          </section>
        </>
      )}
    </main>
  );
}

import { useEffect, useMemo, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { ActivityPackageDraftV1Schema } from "@mathland/contracts/content/schema";

import type { ContentDraft, ValidationReportWire } from "../cloud/cloud_port";
import { useCloud } from "../cloud/cloud_provider";
import { ActivityForm } from "./ActivityForm";
import { AiDraftPanel } from "./AiDraftPanel";
import { diffDraft, type DraftChange } from "./draft_diff";
import { JsonEditor } from "./JsonEditor";
import { PublishDialog } from "./PublishDialog";
import { SamplePreview } from "./SamplePreview";
import { ValidationPanel } from "./ValidationPanel";

type Mode = "form" | "json";
type DraftConflict = {
  remote: ContentDraft;
  mine: DraftChange[];
  theirs: DraftChange[];
};

function concise(value: unknown): string {
  if (value === undefined) return "(변경 없음)";
  const encoded = JSON.stringify(value);
  return encoded.length > 70 ? `${encoded.slice(0, 67)}…` : encoded;
}

function ConflictPanel({ conflict, onAcceptRemote }: { conflict: DraftConflict; onAcceptRemote(): void }) {
  const mineByPath = new Map(conflict.mine.map((change) => [change.path, change]));
  const theirsByPath = new Map(conflict.theirs.map((change) => [change.path, change]));
  const paths = [...new Set([...mineByPath.keys(), ...theirsByPath.keys()])].sort();
  return (
    <section className="studio-section conflict-panel" role="alert">
      <h2>동시 편집 충돌</h2>
      <p>서버 revision {conflict.remote.revision}에 다른 변경이 있습니다. 자동 덮어쓰기는 하지 않았습니다.</p>
      <div className="conflict-table" role="table" aria-label="내 변경과 서버 변경 비교">
        <div role="row" className="conflict-table__head"><span role="columnheader">경로</span><span role="columnheader">내 초안</span><span role="columnheader">서버 최신본</span></div>
        {paths.map((path) => (
          <div role="row" key={path}>
            <code role="cell">{path}</code>
            <span role="cell">{concise(mineByPath.get(path)?.after)}</span>
            <span role="cell">{concise(theirsByPath.get(path)?.after)}</span>
          </div>
        ))}
      </div>
      <p className="fine-print">내 변경은 아래 화면과 고급 JSON에 그대로 남아 있습니다. 서버본을 열면 현재 미저장 변경은 사라집니다.</p>
      <button type="button" onClick={onAcceptRemote}>서버 최신본 열기</button>
    </section>
  );
}

export function DraftEditorPage() {
  const cloud = useCloud();
  const { draftId = "" } = useParams();
  const [record, setRecord] = useState<ContentDraft | null>(null);
  const [base, setBase] = useState<ContentDraft["package"] | null>(null);
  const [draft, setDraft] = useState<ContentDraft["package"] | null>(null);
  const [json, setJson] = useState("");
  const [jsonError, setJsonError] = useState("");
  const [mode, setMode] = useState<Mode>("form");
  const [report, setReport] = useState<ValidationReportWire | null>(null);
  const [pending, setPending] = useState(false);
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");
  const [conflict, setConflict] = useState<DraftConflict | null>(null);
  const [canPublish, setCanPublish] = useState(false);
  const [showPublish, setShowPublish] = useState(false);

  useEffect(() => {
    let current = true;
    void cloud.loadDraft(draftId).then(
      (loaded) => {
        if (!current) return;
        const isolated = structuredClone(loaded.package);
        setRecord(loaded);
        setBase(structuredClone(isolated));
        setDraft(isolated);
        setJson(JSON.stringify(isolated, null, 2));
      },
      () => current && setError("초안을 불러오지 못했습니다."),
    );
    return () => {
      current = false;
    };
  }, [cloud, draftId]);

  useEffect(() => {
    let current = true;
    void cloud.session().then((session) => {
      if (current) setCanPublish(session.status === "authenticated" && session.role === "owner");
    }, () => undefined);
    return () => { current = false; };
  }, [cloud]);

  const changes = useMemo(() => (base && draft ? diffDraft(base, draft) : []), [base, draft]);
  const dirty = changes.length > 0;

  useEffect(() => {
    function warn(event: BeforeUnloadEvent) {
      if (!dirty) return;
      event.preventDefault();
    }
    window.addEventListener("beforeunload", warn);
    return () => window.removeEventListener("beforeunload", warn);
  }, [dirty]);

  useEffect(() => {
    function guardInternalNavigation(event: MouseEvent) {
      if (!dirty || event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
      const element = event.target instanceof Element ? event.target.closest("a[href]") : null;
      if (!element) return;
      const href = element.getAttribute("href");
      if (!href || href.startsWith("#")) return;
      if (!window.confirm("저장하지 않은 변경이 있습니다. 이 화면을 떠날까요?")) {
        event.preventDefault();
        event.stopPropagation();
      }
    }
    window.addEventListener("click", guardInternalNavigation, true);
    return () => window.removeEventListener("click", guardInternalNavigation, true);
  }, [dirty]);

  function updateDraft(next: ContentDraft["package"]) {
    setDraft(next);
    setJson(JSON.stringify(next, null, 2));
    setReport(null);
    setMessage("");
  }

  function updateJson(value: string) {
    setJson(value);
    setJsonError("");
    try {
      const result = ActivityPackageDraftV1Schema.safeParse(JSON.parse(value));
      if (!result.success) {
        setJsonError(result.error.issues[0]?.message ?? "스키마가 올바르지 않습니다.");
        return;
      }
      setDraft(result.data);
      setReport(null);
    } catch {
      setJsonError("JSON 문법을 확인해 주세요.");
    }
  }

  async function save() {
    if (!record || !draft || jsonError) return;
    setPending(true);
    setError("");
    try {
      const saved = await cloud.saveDraft({
        draftId: record.id,
        expectedRevision: record.revision,
        package: draft,
      });
      setRecord(saved);
      setBase(structuredClone(saved.package));
      setDraft(structuredClone(saved.package));
      setJson(JSON.stringify(saved.package, null, 2));
      setMessage(`초안을 저장했습니다. revision ${saved.revision}`);
      setConflict(null);
    } catch {
      try {
        const latest = await cloud.loadDraft(record.id);
        if (latest.revision !== record.revision && base) {
          setConflict({
            remote: latest,
            mine: diffDraft(base, draft),
            theirs: diffDraft(base, latest.package),
          });
          setError("");
          return;
        }
      } catch {
        // Preserve the original save failure when the comparison read is unavailable.
      }
      setError("초안을 저장하지 못했습니다. 연결 상태를 확인한 뒤 다시 시도해 주세요.");
    } finally {
      setPending(false);
    }
  }

  function acceptRemote() {
    if (!conflict) return;
    const latest = conflict.remote;
    const isolated = structuredClone(latest.package);
    setRecord(latest);
    setBase(structuredClone(isolated));
    setDraft(isolated);
    setJson(JSON.stringify(isolated, null, 2));
    setJsonError("");
    setReport(null);
    setConflict(null);
    setMessage(`서버 최신본 revision ${latest.revision}을 열었습니다.`);
  }

  async function validate() {
    if (!record || !draft || jsonError) return;
    setPending(true);
    setError("");
    try {
      setReport(await cloud.validateDraft(record.id, draft));
    } catch {
      setError("검증 서비스를 실행하지 못했습니다.");
    } finally {
      setPending(false);
    }
  }

  if (error && !record) return <main className="state-page" role="alert">{error}</main>;
  if (!record || !draft) return <main className="state-page" aria-busy="true">초안을 여는 중…</main>;

  return (
    <main id="main-content" className="studio-editor">
      <Link className="back-link" to="/studio">← 초안 목록</Link>
      <header className="page-heading">
        <div><p className="eyebrow">{record.activityId} · revision {record.revision}</p><h1>{draft.localizations["ko-KR"].title} 편집</h1></div>
        <div className="editor-actions">
          <button type="button" disabled={pending || Boolean(jsonError)} onClick={() => void validate()}>초안 검증</button>
          <button className="primary-action button-reset" type="button" disabled={pending || Boolean(jsonError) || !dirty || Boolean(conflict)} onClick={() => void save()}>초안 저장</button>
          {canPublish ? <button type="button" disabled={pending || dirty || report?.valid !== true || Boolean(conflict)} onClick={() => setShowPublish(true)}>배포 준비</button> : null}
        </div>
      </header>
      {message ? <p role="status">{message}</p> : null}
      {error ? <p role="alert">{error}</p> : null}
      {conflict ? <ConflictPanel conflict={conflict} onAcceptRemote={acceptRemote} /> : null}
      <div className="filter-row" aria-label="편집 방식">
        <button type="button" aria-pressed={mode === "form"} onClick={() => setMode("form")}>쉬운 설정</button>
        <button type="button" aria-pressed={mode === "json"} onClick={() => setMode("json")}>고급 JSON</button>
      </div>
      {mode === "form" ? <ActivityForm draft={draft} onChange={updateDraft} /> : <JsonEditor value={json} error={jsonError} onChange={updateJson} />}
      {dirty ? <details className="studio-section"><summary>저장 전 변경 {changes.length}개</summary><pre>{JSON.stringify(changes, null, 2)}</pre></details> : null}
      <ValidationPanel report={report} />
      <SamplePreview report={report} />
      <AiDraftPanel
        draft={draft}
        request={(instruction) => cloud.requestAiPatch(record.id, instruction)}
        onApply={updateDraft}
      />
      {showPublish ? <PublishDialog
        draft={record}
        report={report}
        onClose={() => setShowPublish(false)}
        onPublished={(publication) => {
          setShowPublish(false);
          setMessage(`${publication.contentVersion} 버전을 배포했습니다.`);
        }}
      /> : null}
    </main>
  );
}

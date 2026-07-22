export interface JsonEditorProps {
  value: string;
  error: string;
  onChange(value: string): void;
}

export function JsonEditor({ value, error, onChange }: JsonEditorProps) {
  return (
    <section className="studio-section">
      <h2>고급 JSON 편집</h2>
      <p>AI가 없어도 모든 필드를 직접 편집할 수 있습니다. 저장 전에 반드시 검증하세요.</p>
      <label>활동 패키지 JSON
        <textarea className="json-editor" spellCheck={false} value={value} onChange={(event) => onChange(event.currentTarget.value)} />
      </label>
      {error ? <p role="alert">{error}</p> : null}
    </section>
  );
}

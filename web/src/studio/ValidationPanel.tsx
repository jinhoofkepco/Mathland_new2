import type { ValidationReportWire } from "../cloud/cloud_port";

export function ValidationPanel({ report }: { report: ValidationReportWire | null }) {
  if (!report) return null;
  return (
    <section className={`validation-panel ${report.valid ? "is-valid" : "is-invalid"}`} aria-live="polite">
      <h2>{report.valid ? "검증을 통과했습니다" : `수정할 항목 ${report.issues.length}개`}</h2>
      {report.issues.length > 0 ? (
        <ul>{report.issues.map((issue, index) => <li key={`${issue.code}-${index}`}><code>/{issue.path.join("/")}</code> {issue.message}</li>)}</ul>
      ) : <p>이 초안은 샘플 생성과 스키마 검사를 통과했습니다.</p>}
    </section>
  );
}

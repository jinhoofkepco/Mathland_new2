import { useEffect } from "react";
import { Navigate, useSearchParams } from "react-router-dom";

import { useAuth } from "./auth_provider";

function safeNext(raw: string | null): string {
  return raw?.startsWith("/") && !raw.startsWith("//") ? raw : "/dashboard";
}

export function AuthCallbackPage() {
  const { state, refresh } = useAuth();
  const [search] = useSearchParams();

  useEffect(() => {
    void refresh();
  }, [refresh]);

  if (state.status === "authenticated") return <Navigate to={safeNext(search.get("next"))} replace />;
  if (state.status === "onboarding") return <Navigate to="/onboarding" replace />;
  if (state.status === "error") return <main className="state-page" role="alert">{state.message}</main>;
  if (state.status === "unauthorized") {
    return <main className="state-page"><h1>가족 권한을 확인해 주세요</h1></main>;
  }
  if (state.status === "signed_out") {
    return <Navigate to={`/login?next=${encodeURIComponent(safeNext(search.get("next")))}`} replace />;
  }
  return <main className="state-page" aria-busy="true">안전한 로그인 링크를 확인하고 있어요…</main>;
}

import type { PropsWithChildren } from "react";
import { Navigate, useLocation } from "react-router-dom";

import { useAuth } from "./auth_provider";

export function RequireSession({ children }: PropsWithChildren) {
  const { state } = useAuth();
  const location = useLocation();

  if (state.status === "loading") {
    return <main className="state-page" aria-busy="true">세션을 확인하고 있어요…</main>;
  }
  if (state.status === "error") {
    return <main className="state-page" role="alert">{state.message}</main>;
  }
  if (state.status === "signed_out") {
    const next = `${location.pathname}${location.search}`;
    return <Navigate to={`/login?next=${encodeURIComponent(next)}`} replace />;
  }
  if (state.status === "onboarding") {
    const next = `${location.pathname}${location.search}`;
    return <Navigate to={`/onboarding?next=${encodeURIComponent(next)}`} replace />;
  }
  if (state.status === "unauthorized") {
    return (
      <main className="state-page">
        <h1>가족 권한이 필요합니다</h1>
        <p>초대받은 보호자 계정인지 확인해 주세요.</p>
      </main>
    );
  }
  return children;
}

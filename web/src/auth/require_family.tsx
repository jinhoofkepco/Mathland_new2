import type { PropsWithChildren } from "react";
import { Navigate, useLocation } from "react-router-dom";

import { useAuth } from "./auth_provider";

export function RequireFamily({ children }: PropsWithChildren) {
  const { state } = useAuth();
  const location = useLocation();

  if (state.status !== "authenticated") return children;
  if (state.familyStatus === "onboarding") {
    const next = `${location.pathname}${location.search}`;
    return <Navigate to={`/onboarding?next=${encodeURIComponent(next)}`} replace />;
  }
  if (state.familyStatus === "unauthorized") {
    return (
      <main className="state-page">
        <h1>가족 권한이 필요합니다</h1>
        <p>이 계정의 가족 권한을 확인해 주세요.</p>
      </main>
    );
  }
  return children;
}

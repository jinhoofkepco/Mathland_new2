import type { PropsWithChildren } from "react";

import type { GuardianRole } from "../cloud/cloud_port";
import { useAuth } from "./auth_provider";
import { RequireSession } from "./require_session";

export interface RequireRoleProps extends PropsWithChildren {
  allow: GuardianRole[];
}

function RoleBoundary({ allow, children }: RequireRoleProps) {
  const { state } = useAuth();
  if (state.status !== "authenticated") return null;
  if (!allow.includes(state.role)) {
    return (
      <main className="state-page">
        <p className="eyebrow">권한 403</p>
        <h1>접근할 수 없는 화면입니다</h1>
        <p>이 계정에는 해당 작업 권한이 없습니다.</p>
      </main>
    );
  }
  return children;
}

export function RequireRole({ allow, children }: RequireRoleProps) {
  return (
    <RequireSession>
      <RoleBoundary allow={allow}>{children}</RoleBoundary>
    </RequireSession>
  );
}

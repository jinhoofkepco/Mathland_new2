import type { PropsWithChildren } from "react";
import { NavLink, useNavigate } from "react-router-dom";

import { useAuth } from "../auth/auth_provider";

export function AppLayout({ children }: PropsWithChildren) {
  const { state, signOut } = useAuth();
  const navigate = useNavigate();
  const canEdit = state.status === "authenticated" && (state.role === "editor" || state.role === "owner");

  async function exit() {
    await signOut();
    navigate("/login", { replace: true });
  }

  return (
    <div className="app-layout">
      <header className="app-header">
        <NavLink className="wordmark" to="/dashboard">MathLand 보호자</NavLink>
        <button className="quiet-button" type="button" onClick={() => void exit()}>로그아웃</button>
      </header>
      <nav className="app-nav" aria-label="보호자 메뉴">
        <NavLink to="/dashboard">학습 현황</NavLink>
        <NavLink to="/devices">기기 연결</NavLink>
        <NavLink to="/data">데이터 관리</NavLink>
        {canEdit ? <NavLink to="/studio">콘텐츠 스튜디오</NavLink> : null}
      </nav>
      <div className="app-content">{children}</div>
    </div>
  );
}

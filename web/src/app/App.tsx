import { Link, Route, Routes } from "react-router-dom";

import { AuthCallbackPage } from "../auth/AuthCallbackPage";
import { LoginPage } from "../auth/LoginPage";
import { RequireRole } from "../auth/require_role";
import { RequireSession } from "../auth/require_session";
import { DashboardPage } from "../dashboard/DashboardPage";
import { DataControlsPage } from "../data/DataControlsPage";
import { DevicesPage } from "../devices/DevicesPage";
import { AppLayout } from "../layout/AppLayout";

function WelcomePage() {
  return (
    <main id="main-content" className="welcome-shell">
      <section className="welcome-card" aria-labelledby="welcome-title">
        <div className="brand-mark" aria-hidden="true">
          <span className="brand-mark__ear brand-mark__ear--left" />
          <span className="brand-mark__ear brand-mark__ear--right" />
          <span className="brand-mark__face">⌣</span>
        </div>
        <p className="eyebrow">아이의 수학 탐험을 가까이에서</p>
        <h1 id="welcome-title">MathLand 보호자</h1>
        <p className="welcome-copy">
          학습 흐름을 확인하고, 난이도와 새 활동을 아이에게 맞게 조절하세요.
        </p>
        <Link className="primary-action" to="/login">
          이메일로 시작하기
          <span aria-hidden="true">→</span>
        </Link>
        <p className="privacy-note">아이의 플레이는 인터넷이 없어도 안전하게 이어집니다.</p>
      </section>
      <aside className="island-preview" aria-label="MathLand 탐험 안내">
        <span className="island-preview__sun" aria-hidden="true" />
        <div className="island-preview__content">
          <p>오늘의 탐험</p>
          <strong>수 감각 섬 · 3개 활동</strong>
          <div className="progress-track" aria-hidden="true">
            <span />
          </div>
        </div>
      </aside>
    </main>
  );
}

function StudioPlaceholder() {
  return (
    <main id="main-content" className="management-page">
      <p className="eyebrow">현장에서 바로 바꾸는 활동 설정</p>
      <h1>콘텐츠 스튜디오</h1>
      <p>검증된 초안만 저장·미리보기·배포할 수 있습니다.</p>
    </main>
  );
}

function ProtectedPage({ children }: { children: React.ReactNode }) {
  return (
    <RequireSession>
      <AppLayout>{children}</AppLayout>
    </RequireSession>
  );
}

export function App() {
  return (
    <>
      <a className="skip-link" href="#main-content">
        본문으로 바로가기
      </a>
      <Routes>
        <Route path="/" element={<WelcomePage />} />
        <Route path="/login" element={<LoginPage />} />
        <Route path="/auth/callback" element={<AuthCallbackPage />} />
        <Route path="/dashboard" element={<ProtectedPage><DashboardPage /></ProtectedPage>} />
        <Route path="/dashboard/:familyId/:profileId" element={<ProtectedPage><DashboardPage /></ProtectedPage>} />
        <Route path="/devices" element={<ProtectedPage><DevicesPage /></ProtectedPage>} />
        <Route path="/data" element={<ProtectedPage><DataControlsPage /></ProtectedPage>} />
        <Route
          path="/studio/*"
          element={
            <ProtectedPage>
              <RequireRole allow={["editor", "owner"]}><StudioPlaceholder /></RequireRole>
            </ProtectedPage>
          }
        />
        <Route path="*" element={<main className="state-page"><h1>화면을 찾을 수 없습니다</h1><Link to="/">처음으로</Link></main>} />
      </Routes>
    </>
  );
}

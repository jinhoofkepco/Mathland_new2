import {
  createContext,
  type PropsWithChildren,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
} from "react";

import type { SessionState } from "../cloud/cloud_port";
import { useCloud } from "../cloud/cloud_provider";

type AuthState =
  | { status: "loading" }
  | { status: "error"; message: string }
  | SessionState;

interface AuthContextValue {
  state: AuthState;
  refresh(): Promise<void>;
  signOut(): Promise<void>;
}

const AuthContext = createContext<AuthContextValue | null>(null);

function errorMessage(error: unknown): string {
  return error instanceof Error && error.message.trim() !== ""
    ? error.message
    : "세션을 확인하지 못했습니다.";
}

export function AuthProvider({ children }: PropsWithChildren) {
  const cloud = useCloud();
  const [state, setState] = useState<AuthState>({ status: "loading" });

  const refresh = useCallback(async () => {
    setState({ status: "loading" });
    try {
      setState(await cloud.session());
    } catch (error) {
      setState({ status: "error", message: errorMessage(error) });
    }
  }, [cloud]);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  const signOut = useCallback(async () => {
    await cloud.signOut();
    setState({ status: "signed_out" });
  }, [cloud]);

  const value = useMemo(() => ({ state, refresh, signOut }), [state, refresh, signOut]);
  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthContextValue {
  const value = useContext(AuthContext);
  if (!value) throw new Error("useAuth must be used inside AuthProvider");
  return value;
}

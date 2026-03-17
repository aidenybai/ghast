import { Layout } from "./components/Layout";
import { useKeyboardShortcuts } from "./hooks/useKeyboardShortcuts";

export function App() {
  useKeyboardShortcuts();

  return (
    <div className="h-screen w-screen bg-[#1e1e2e] text-white overflow-hidden">
      <Layout />
    </div>
  );
}

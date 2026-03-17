/** Global registry mapping tab IDs to ghostty-web Terminal instances. */

type Terminal = any; // Will be typed when ghostty-web is imported

const terminals = new Map<string, Terminal>();

export const terminalRegistry = {
  get(id: string): Terminal | undefined {
    return terminals.get(id);
  },

  set(id: string, term: Terminal): void {
    terminals.set(id, term);
  },

  delete(id: string): void {
    const term = terminals.get(id);
    if (term) {
      try {
        term.dispose();
      } catch {}
      terminals.delete(id);
    }
  },

  has(id: string): boolean {
    return terminals.has(id);
  },
};

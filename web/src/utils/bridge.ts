export type BridgeMode = 'nui' | 'dui' | 'browser';

export interface DuiBridgeInfo {
  resourceName?: string;
  duiWidth?: number;
  duiHeight?: number;
}

const state: {
  resourceName: string | null;
  duiWidth: number | null;
  duiHeight: number | null;
} = {
  resourceName: null,
  duiWidth: null,
  duiHeight: null,
};

export const setDuiBridgeInfo = (info?: DuiBridgeInfo) => {
  if (!info) return;
  if (info.resourceName) state.resourceName = info.resourceName;
  if (typeof info.duiWidth === 'number') state.duiWidth = info.duiWidth;
  if (typeof info.duiHeight === 'number') state.duiHeight = info.duiHeight;
};

export const getBridgeMode = (): BridgeMode => {
  const w = window as any;
  if (typeof w.GetParentResourceName === 'function') return 'nui';
  if (state.resourceName) return 'dui';
  return 'browser';
};

export const getBridgeResourceName = (): string | null => {
  const w = window as any;
  if (typeof w.GetParentResourceName === 'function') {
    try {
      return w.GetParentResourceName();
    } catch (_) {
      return null;
    }
  }
  return state.resourceName;
};

export const getDuiBridgeInfo = () => ({ ...state });

window.addEventListener('message', (event: MessageEvent) => {
  const payload = event.data;
  if (!payload || payload.action !== 'bridgeReady') return;
  setDuiBridgeInfo(payload.data as DuiBridgeInfo);
});

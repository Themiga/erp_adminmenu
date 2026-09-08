import {getBridgeMode, getBridgeResourceName} from './bridge';

export interface NuiFailure {
  ok: false;
  error: string;
}

const browserMock = (eventName: string): any => {
  if (eventName === 'playerList') return [];
  if (eventName === 'getPlayerInfo') {
    return {
      ok: true,
      serverId: 0,
      health: 200,
      armor: 0,
      coords: {x: 0, y: 0, z: 0},
      heading: 0,
      mock: true,
    };
  }
  if (eventName === 'getVehicleInfo') {
    return {ok: true, inVehicle: false, mock: true};
  }
  return {ok: true, mock: true};
};

export async function fetchNui<T = any>(eventName: string, data?: any, timeoutMs = 3000): Promise<T> {
  const mode = getBridgeMode();

  if (mode === 'browser') {
    return browserMock(eventName) as T;
  }

  const resourceName = getBridgeResourceName();
  if (!resourceName) {
    return {ok: false, error: 'missing_resource_name'} as unknown as T;
  }

  const controller = typeof AbortController !== 'undefined' ? new AbortController() : undefined;
  const timeout = window.setTimeout(() => controller && controller.abort(), timeoutMs);

  try {
    const response = await fetch(`https://${resourceName}/${eventName}`, {
      method: 'post',
      headers: {
        'Content-Type': 'application/json; charset=UTF-8',
      },
      body: JSON.stringify(data || {}),
      signal: controller ? controller.signal : undefined,
    });

    if (!response.ok) {
      return {ok: false, error: `http_${response.status}`} as unknown as T;
    }

    const text = await response.text();
    if (!text) return {ok: true} as unknown as T;

    try {
      return JSON.parse(text) as T;
    } catch (_) {
      return text as unknown as T;
    }
  } catch (error) {
    const reason = error instanceof Error ? error.message : 'transport_failed';
    return {ok: false, error: reason} as unknown as T;
  } finally {
    window.clearTimeout(timeout);
  }
}

export const sendGameAction = <T = any>(action: string, data?: any, timeoutMs?: number) =>
  fetchNui<T>(action, data, timeoutMs);

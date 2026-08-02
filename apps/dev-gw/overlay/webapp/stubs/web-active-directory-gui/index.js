// devget build-only stub — see ../README.md.
import { InjectionToken } from '@angular/core';

export const AD_DATA_PROVIDER = new InjectionToken('AD_DATA_PROVIDER');
export const AD_SESSION_MANAGER = new InjectionToken('AD_SESSION_MANAGER');
export const AD_TRANSLATOR = new InjectionToken('AD_TRANSLATOR');
export const AD_UI = new InjectionToken('AD_UI');

export const AdConnectionEventType = Object.freeze({
  Connected: 'Connected',
  Terminated: 'Terminated',
  Error: 'Error',
  Warning: 'Warning',
  Success: 'Success',
});

export function matchTranslateKey(code) {
  return String(code ?? '');
}

export function normalizeError(error) {
  return error instanceof Error ? error : new Error(String(error));
}

// devget build-only stub — see ../README.md.
// AdDataProvider/AdSessionManager/AdTranslator/AdUi are `implements` targets, so
// they must stay interfaces; the rest are annotation-only and stay permissive.
import { InjectionToken } from '@angular/core';

export declare const AD_DATA_PROVIDER: InjectionToken<unknown>;
export declare const AD_SESSION_MANAGER: InjectionToken<unknown>;
export declare const AD_TRANSLATOR: InjectionToken<unknown>;
export declare const AD_UI: InjectionToken<unknown>;

export declare const AdConnectionEventType: Record<string, string>;

export declare function matchTranslateKey(code: unknown): string;
export declare function normalizeError(error: unknown): Error;

export interface AdDataProvider {}
export interface AdSessionManager {}
export interface AdTranslator {}
export interface AdUi {}

// gateway-ui derives parameter types from these via Parameters<...>, so the
// members have to stay callable rather than collapsing to `any`.
export interface LdapSessionLike {
    [key: string]: (...args: any[]) => any;
}

export type ActiveDirectoryConnectionParams = any;
export type ActiveDirectoryMainHandle = any;
export type AdAddRequest = any;
export type AdBindRequest = any;
export type AdBindResult = any;
export type AdCapabilities = any;
export type AdConnectionError = any;
export type AdDeleteRequest = any;
export type AdModifyDnRequest = any;
export type AdModifyRequest = any;
export type AdPageControl = any;
export type AdPageResult = any;
export type AdResult = any;
export type AdSearchParams = any;
export type AdSearchResult = any;
export type AdUiConfirmOptions = any;
export type AdUiToastOptions = any;
export type AdWebSessionConfig = any;
export type LdapControlArrayLike = any;
export type LdapResultLike = any;
export type SearchEntryLike = any;
export type SearchMessageLike = any;

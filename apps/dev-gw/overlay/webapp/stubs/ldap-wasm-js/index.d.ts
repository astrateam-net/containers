// devget build-only stub — see ../README.md.
// Only the symbols gateway-ui imports; the LDAP request/result shapes stay
// permissive because nothing in the RDP path constructs them.
export default function init(): Promise<void>;

export declare function set_logging_level(level: number): void;

export declare const LoggingLevel: Record<string, number>;

export declare class LdapSession {
    static connect(parameters: LdapSessionParameters): Promise<any>;
    [key: string]: any;
}

export declare class LdapSessionParameters {
    constructor(url: string, decoderMaxBytes?: number);
    [key: string]: any;
}

export type Attribute = any;
export type AttributesArray = any;
export type BinaryLdapModifies = any;
export type LdapControl = any;
export type LdapControlArray = any;
export type LdapResult = any;
export type ModifyRequest = any;
export type SaslBindConfig = any;
export type SearchParameters = any;
export type SspiAuthMethod = any;

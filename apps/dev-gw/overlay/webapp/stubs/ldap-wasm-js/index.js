// devget build-only stub — see ../README.md.
const unavailable = () => {
  throw new Error('Active Directory sessions are not available in this build.');
};

export default function init() {
  return Promise.resolve();
}

export function set_logging_level() {}

export const LoggingLevel = Object.freeze({
  Trace: 0,
  Debug: 1,
  Info: 2,
  Warn: 3,
  Error: 4,
  Off: 5,
});

export const SspiAuthMethod = Object.freeze({
  Negotiate: 0,
  Kerberos: 1,
  Ntlm: 2,
});

export class LdapSession {
  static connect = unavailable;
}

export class LdapSessionParameters {}
export class Attribute {}
export class AttributesArray {}
export class BinaryLdapModifies {}
export class LdapControl {}
export class LdapControlArray {}
export class LdapResult {}
export class ModifyRequest {}
export class SaslBindConfig {}
export class SearchParameters {}

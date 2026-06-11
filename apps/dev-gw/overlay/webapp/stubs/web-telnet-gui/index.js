// devget build-only stub — see ../README.md.
export const TerminalConnectionStatus = Object.freeze({
  connected: 0,
  connecting: 1,
  closed: 2,
  failed: 3,
  timeout: 4,
});

export const LoggingLevel = Object.freeze({
  TRACE: 0,
  DEBUG: 1,
  INFO: 2,
  WARN: 3,
  ERROR: 4,
  FATAL: 5,
  OFF: 6,
});

export const loggingService = {
  setLevel() {},
};

export class TelnetTerminal {}

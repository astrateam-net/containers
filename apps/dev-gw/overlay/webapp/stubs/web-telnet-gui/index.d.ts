// devget build-only stub — see ../README.md.
export declare enum TerminalConnectionStatus {
    connected = 0,
    connecting = 1,
    closed = 2,
    failed = 3,
    timeout = 4,
}

export declare enum LoggingLevel {
    TRACE = 0,
    DEBUG = 1,
    INFO = 2,
    WARN = 3,
    ERROR = 4,
    FATAL = 5,
    OFF = 6,
}

export declare const loggingService: {
    setLevel(level: LoggingLevel | number): void;
};

export declare class TelnetTerminal {
    [key: string]: any;
}

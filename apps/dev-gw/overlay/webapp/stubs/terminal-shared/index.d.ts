// devget build-only stub — see ../README.md.
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

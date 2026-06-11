// devget build-only stub — see ../README.md.
export declare enum TerminalConnectionStatus {
    connected = 0,
    connecting = 1,
    closed = 2,
    failed = 3,
    timeout = 4,
}

export declare const loggingService: {
    setLevel(level: number): void;
};

export declare class SSHTerminal {
    [key: string]: any;
}

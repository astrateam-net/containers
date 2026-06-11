// devget build-only stub — see ../README.md.
// The VNC/ARD web sessions are inert in this edition; only the symbols the
// gateway-ui components import are provided.

export async function init(_logLevel) {}

export const Backend = {};

const stubExtension = (ident) => (value) => ({ ident: `devget-stub:${ident}`, value });

export const ardQualityMode = stubExtension('ard_quality_mode');
export const dynamicResizingSupportedCallback = stubExtension('dynamic_resizing_supported_callback');
export const enableCursor = stubExtension('enable_cursor');
export const enabledEncodings = stubExtension('enabled_encodings');
export const enableExtendedClipboard = stubExtension('enable_extended_clipboard');
export const jpegQualityLevel = stubExtension('jpeg_quality_level');
export const pixelFormat = stubExtension('pixel_format');
export const resolutionQuality = stubExtension('resolution_quality');
export const ultraVirtualDisplay = stubExtension('ultra_virtual_display');
export const wheelSpeedFactor = stubExtension('wheel_speed_factor');

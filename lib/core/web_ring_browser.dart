import 'dart:convert';
import 'dart:js_interop';

@JS('yaraWeb.initialize')
external void _initialize(JSFunction callback);
@JS('yaraWeb.playRing')
external void _play();
@JS('yaraWeb.stopRing')
external void _stop();
@JS('yaraWeb.legacyToken')
external JSString? _legacyToken();
@JS('yaraWeb.legacyDeviceId')
external JSString? _legacyDeviceId();
@JS('yaraWeb.clearLegacyToken')
external void _clearLegacyToken();

void initializeWebRing(void Function(Map<String, dynamic>) onAlert) {
  _initialize(
    ((JSString value) {
      try {
        onAlert((jsonDecode(value.toDart) as Map).cast<String, dynamic>());
      } catch (_) {
        /* A malformed browser message cannot open a lesson. */
      }
    }).toJS,
  );
}

void playWebRing() => _play();
void stopWebRing() => _stop();
String? legacyWebToken() => _legacyToken()?.toDart;
String? legacyWebDeviceId() => _legacyDeviceId()?.toDart;
void clearLegacyWebToken() => _clearLegacyToken();

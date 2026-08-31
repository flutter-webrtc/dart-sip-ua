import 'constants.dart' as DartSIP_C;
import 'constants.dart';
import 'enums.dart';
import 'event_manager/event_manager.dart';
import 'event_manager/internal_events.dart';
import 'exceptions.dart' as Exceptions;
import 'logger.dart';
import 'request_sender.dart';
import 'sip_message.dart';
import 'ua.dart';
import 'uri.dart';
import 'utils.dart' as Utils;

/// Lightweight SIP PUBLISH (RFC 3903) sender.
///
/// Publishes presence/status information to the SIP server.
/// Tracks the SIP-ETag from the server for conditional publication
/// on subsequent PUBLISH requests.
class Publish extends EventManager {
  Publish(this._ua);

  final UA _ua;
  dynamic _request;
  bool _closed = false;
  String? _etag;

  /// The SIP-ETag returned by the server on the last successful PUBLISH.
  /// Include this as SIP-If-Match on the next publish for this event package.
  String? get etag => _etag;

  /// Send a PUBLISH request.
  ///
  /// [target] is the SIP URI to publish to (typically your own AOR).
  /// [body] is the PIDF XML presence document (RFC 3863).
  /// [expires] controls how long the server retains this publication (default 3600).
  /// [contentType] must be 'application/pidf+xml' for RFC 3903 compliance.
  /// [sipIfMatch] is the SIP-ETag from a previous publication, for conditional updates.
  /// [extraHeaders] are any additional SIP headers.
  void send(
    String target,
    String body, {
    int expires = 3600,
    String contentType = 'application/pidf+xml',
    String? sipIfMatch,
    Map<String, dynamic>? params,
    Map<String, dynamic>? options,
  }) {
    final String originalTarget = target;
    options = options ?? <String, dynamic>{};

    if (target.isEmpty || body.isEmpty) {
      throw Exceptions.TypeError(
          'Not enough arguments: target and body required');
    }

    // Check target validity.
    final URI? normalized = _ua.normalizeTarget(target);
    if (normalized == null) {
      throw Exceptions.TypeError('Invalid target: $originalTarget');
    }

    // Build extra headers.
    final List<dynamic> extraHeaders =
        Utils.cloneArray(options['extraHeaders'] ?? <dynamic>[]);
    final EventManager eventHandlers =
        options['eventHandlers'] ?? EventManager();

    // Set event handlers from caller.
    addAllEventHandlers(eventHandlers);

    // Content-Type for PIDF.
    extraHeaders.add('Content-Type: $contentType');

    // Event header (RFC 3903 Section 6.1).
    extraHeaders.add('Event: presence');

    // Expires header.
    extraHeaders.add('Expires: $expires');

    // Conditional publication (RFC 3903 Section 6.3).
    if (sipIfMatch != null && sipIfMatch.isNotEmpty) {
      extraHeaders.add('SIP-If-Match: $sipIfMatch');
    }

    _request = OutgoingRequest(
        SipMethod.PUBLISH, normalized, _ua, params, extraHeaders);
    _request.body = body;

    final EventManager handlers = EventManager();
    handlers.on(EventOnRequestTimeout(), (EventOnRequestTimeout value) {
      _onRequestTimeout();
    });
    handlers.on(EventOnTransportError(), (EventOnTransportError value) {
      _onTransportError();
    });
    handlers.on(EventOnReceiveResponse(), (EventOnReceiveResponse event) {
      _receiveResponse(event.response);
    });

    final RequestSender requestSender = RequestSender(_ua, _request, handlers);
    requestSender.send();
  }

  void _receiveResponse(IncomingResponse? response) {
    if (_closed) return;

    if (response == null) return;

    final int? statusCode = response.status_code;

    // 1xx — provisional, ignore.
    if (statusCode != null && statusCode >= 100 && statusCode < 200) {
      return;
    }

    // 2xx — success.
    if (statusCode != null && statusCode >= 200 && statusCode < 300) {
      // Extract SIP-ETag for conditional publication on next PUBLISH.
      final dynamic etagHeader = response.getHeader('SIP-ETag');
      if (etagHeader != null && etagHeader is String && etagHeader.isNotEmpty) {
        _etag = etagHeader;
      }

      // Extract Expires to know how long the server will retain this.
      final dynamic expiresHeader = response.getHeader('Expires');
      int? serverExpires;
      if (expiresHeader != null && expiresHeader is String) {
        serverExpires = int.tryParse(expiresHeader);
      }

      logger.d('PUBLISH succeeded'
          '${_etag != null ? ', etag=$_etag' : ''}'
          '${serverExpires != null ? ', expires=$serverExpires' : ''}');

      _succeeded(response);
      return;
    }

    // 412 Conditional Request Failed — need to refresh (no ETag, or expired).
    if (statusCode == 412) {
      logger.d('PUBLISH 412 — conditional request failed, clearing etag');
      _etag = null;
      _failed(412, DartSIP_C.CausesType.SIP_FAILURE_CODE,
          'Conditional Request Failed');
      return;
    }

    // 423 Interval Too Brief — server wants a longer expiry.
    if (statusCode == 423) {
      final dynamic minExpires = response.getHeader('Min-Expires');
      logger.d('PUBLISH 423 — interval too brief, min-expires=$minExpires');
      _failed(423, DartSIP_C.CausesType.SIP_FAILURE_CODE,
          'Interval Too Brief (Min-Expires: $minExpires)');
      return;
    }

    // Any other failure.
    final String cause = Utils.sipErrorCause(response.status_code);
    _failed(
        statusCode ?? 500, cause, response.reason_phrase ?? 'PUBLISH failed');
  }

  void _onRequestTimeout() {
    if (_closed) return;
    _failed(408, DartSIP_C.CausesType.REQUEST_TIMEOUT, 'Request Timeout');
  }

  void _onTransportError() {
    if (_closed) return;
    _failed(500, DartSIP_C.CausesType.CONNECTION_ERROR, 'Transport Error');
  }

  void _succeeded(IncomingResponse response) {
    close();
    logger.d('emit "succeeded"');
    emit(EventSucceeded(originator: Originator.local, response: response));
  }

  void _failed(int statusCode, String cause, String reasonPhrase) {
    logger.d('PUBLISH failed: $reasonPhrase');
    close();
    logger.d('emit "failed"');
    emit(EventCallFailed(
        originator: Originator.local,
        cause: ErrorCause(
            cause: cause,
            status_code: statusCode,
            reason_phrase: reasonPhrase)));
  }

  void close() {
    _closed = true;
  }
}

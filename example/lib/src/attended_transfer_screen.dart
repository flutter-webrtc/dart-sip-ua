import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:sip_ua/sip_ua.dart';

/// Arguments passed to the AttendedTransferScreen.
class AttendedTransferArgs {
  /// The original call that will be transferred.
  final Call originalCall;

  /// The target URI/number to call for consultation.
  final String targetUri;

  /// The SIP UA helper instance.
  final SIPUAHelper helper;

  AttendedTransferArgs({
    required this.originalCall,
    required this.targetUri,
    required this.helper,
  });
}

/// Screen that manages the attended transfer flow.
///
/// This screen:
/// 1. Holds the original call
/// 2. Initiates a consultation call to the target
/// 3. Allows the user to complete or cancel the transfer
class AttendedTransferScreen extends StatefulWidget {
  final AttendedTransferArgs args;

  /// Static flag to indicate if attended transfer flow is active.
  /// Used to prevent dialpad from navigating to a new CallScreen
  /// when the consultation call is initiated.
  static bool isAttendedTransferActive = false;

  const AttendedTransferScreen({Key? key, required this.args})
      : super(key: key);

  @override
  State<AttendedTransferScreen> createState() => _AttendedTransferScreenState();
}

class _AttendedTransferScreenState extends State<AttendedTransferScreen>
    implements SipUaHelperListener {
  RTCVideoRenderer? _localRenderer = RTCVideoRenderer();
  RTCVideoRenderer? _remoteRenderer = RTCVideoRenderer();

  Call? _consultationCall;
  CallStateEnum _consultationCallState = CallStateEnum.NONE;
  String _statusMessage = 'Initiating consultation call...';
  bool _isTransferring = false;
  bool _transferComplete = false;
  String? _errorMessage;
  bool _isPopping = false; // Prevent multiple pops

  final ValueNotifier<String> _timeLabel = ValueNotifier<String>('00:00');
  Timer? _timer;

  Call get originalCall => widget.args.originalCall;
  String get targetUri => widget.args.targetUri;
  SIPUAHelper get helper => widget.args.helper;

  @override
  void initState() {
    super.initState();
    // Set flag to prevent dialpad from opening a new call screen
    AttendedTransferScreen.isAttendedTransferActive = true;
    _initRenderers();
    helper.addSipUaHelperListener(this);
    // Use addPostFrameCallback to avoid setState during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startAttendedTransferFlow();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    helper.removeSipUaHelperListener(this);
    _disposeRenderers();
    // Clear the flag when screen is disposed
    AttendedTransferScreen.isAttendedTransferActive = false;
    super.dispose();
  }

  void _initRenderers() async {
    await _localRenderer?.initialize();
    await _remoteRenderer?.initialize();
  }

  void _disposeRenderers() {
    _localRenderer?.dispose();
    _localRenderer = null;
    _remoteRenderer?.dispose();
    _remoteRenderer = null;
  }

  /// Starts the attended transfer flow:
  /// 1. Hold the original call
  /// 2. Make the consultation call
  void _startAttendedTransferFlow() async {
    if (!mounted) return;

    setState(() {
      _statusMessage = 'Holding original call...';
    });

    // Hold the original call
    originalCall.hold();

    // Small delay to ensure hold is processed
    await Future.delayed(Duration(milliseconds: 500));

    if (!mounted) return;

    setState(() {
      _statusMessage = 'Calling $targetUri...';
    });

    // Make the consultation call
    await helper.call(targetUri, voiceOnly: true);
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(Duration(seconds: 1), (Timer timer) {
      Duration duration = Duration(seconds: timer.tick);
      if (mounted) {
        _timeLabel.value = [duration.inMinutes, duration.inSeconds]
            .map((seg) => seg.remainder(60).toString().padLeft(2, '0'))
            .join(':');
      } else {
        _timer?.cancel();
      }
    });
  }

  /// Completes the attended transfer.
  void _completeTransfer() {
    if (_consultationCall == null) {
      if (mounted) {
        setState(() {
          _errorMessage = 'No consultation call available';
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isTransferring = true;
        _statusMessage = 'Completing transfer...';
      });
    }

    final referSubscriber = originalCall.attendedTransfer(
      _consultationCall!,
      onTrying: () {
        if (mounted) {
          setState(() {
            _statusMessage = 'Transfer in progress...';
          });
        }
      },
      onProgress: (statusLine) {
        if (mounted) {
          setState(() {
            _statusMessage = 'Transfer progress: ${statusLine ?? "..."}';
          });
        }
      },
      onAccepted: () {
        if (mounted) {
          setState(() {
            _transferComplete = true;
            _statusMessage = 'Transfer successful!';
          });
          // Close this screen after a short delay
          Future.delayed(Duration(seconds: 2), () {
            _safePop(transferSucceeded: true);
          });
        }
      },
      onFailed: (statusLine) {
        if (mounted) {
          setState(() {
            _isTransferring = false;
            _errorMessage = 'Transfer failed: ${statusLine ?? "Unknown error"}';
            _statusMessage = 'Transfer failed';
          });
        }
      },
    );

    if (referSubscriber == null) {
      if (mounted) {
        setState(() {
          _isTransferring = false;
          _errorMessage =
              'Failed to initiate transfer. Missing dialog information.';
        });
      }
    }
  }

  /// Cancels the attended transfer flow.
  /// Hangs up the consultation call and unholds the original call.
  void _cancelTransfer() {
    // Hang up the consultation call if it exists
    if (_consultationCall != null &&
        _consultationCallState != CallStateEnum.ENDED &&
        _consultationCallState != CallStateEnum.FAILED) {
      _consultationCall!.hangup();
    }

    // Unhold the original call
    originalCall.unhold();

    // Go back to call screen
    _safePop();
  }

  /// Safely pops the screen, preventing multiple pops and Navigator lock issues.
  /// [transferSucceeded] indicates whether the transfer was successful.
  void _safePop({bool transferSucceeded = false}) {
    if (_isPopping || !mounted) return;
    _isPopping = true;

    // Use WidgetsBinding to ensure we pop after any pending navigation operations
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop(transferSucceeded);
      }
    });
  }

  @override
  void callStateChanged(Call call, CallState callState) {
    // Check if this is our consultation call (not the original call)
    if (call.id != originalCall.id) {
      if (!mounted) return;

      setState(() {
        _consultationCall = call;
        _consultationCallState = callState.state;
      });

      switch (callState.state) {
        case CallStateEnum.CALL_INITIATION:
          if (mounted) {
            setState(() {
              _statusMessage = 'Initiating call to $targetUri...';
            });
          }
          break;

        case CallStateEnum.CONNECTING:
          if (mounted) {
            setState(() {
              _statusMessage = 'Connecting to $targetUri...';
            });
          }
          break;

        case CallStateEnum.PROGRESS:
          if (mounted) {
            setState(() {
              _statusMessage = 'Ringing $targetUri...';
            });
          }
          break;

        case CallStateEnum.ACCEPTED:
        case CallStateEnum.CONFIRMED:
          _startTimer();
          if (mounted) {
            setState(() {
              _statusMessage = 'Connected to $targetUri';
            });
          }
          break;

        case CallStateEnum.STREAM:
          _handleStream(callState);
          break;

        case CallStateEnum.FAILED:
          if (mounted) {
            setState(() {
              _statusMessage = 'Call failed';
              _errorMessage = callState.cause?.cause ?? 'Call failed';
            });
          }
          // Unhold original call on failure
          Future.delayed(Duration(seconds: 2), () {
            originalCall.unhold();
            _safePop();
          });
          break;

        case CallStateEnum.ENDED:
          if (!_transferComplete) {
            if (mounted) {
              setState(() {
                _statusMessage = 'Consultation call ended';
              });
            }
            // If transfer wasn't completed, unhold original call
            originalCall.unhold();
            Future.delayed(Duration(seconds: 1), () {
              _safePop();
            });
          }
          break;

        default:
          break;
      }
    }
  }

  void _handleStream(CallState event) {
    MediaStream? stream = event.stream;
    if (event.originator == Originator.local) {
      if (_localRenderer != null) {
        _localRenderer!.srcObject = stream;
      }
      // enableSpeakerphone is only available on mobile platforms (iOS/Android)
      if (!kIsWeb &&
          !Platform.isMacOS &&
          !Platform.isLinux &&
          !Platform.isWindows &&
          event.stream?.getAudioTracks().isNotEmpty == true) {
        try {
          event.stream?.getAudioTracks().first.enableSpeakerphone(false);
        } catch (e) {
          // Ignore speakerphone errors on unsupported platforms
        }
      }
    }
    if (event.originator == Originator.remote) {
      if (_remoteRenderer != null) {
        _remoteRenderer!.srcObject = stream;
      }
    }
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void transportStateChanged(TransportState state) {}

  @override
  void registrationStateChanged(RegistrationState state) {}

  @override
  void onNewMessage(SIPMessageRequest msg) {}

  @override
  void onNewNotify(Notify ntf) {}

  @override
  void onNewReinvite(ReInvite event) {}

  Widget _buildStatusSection() {
    Color statusColor = Colors.blue;
    IconData statusIcon = Icons.phone_forwarded;

    if (_transferComplete) {
      statusColor = Colors.green;
      statusIcon = Icons.check_circle;
    } else if (_errorMessage != null) {
      statusColor = Colors.red;
      statusIcon = Icons.error;
    } else if (_consultationCallState == CallStateEnum.CONFIRMED ||
        _consultationCallState == CallStateEnum.ACCEPTED) {
      statusColor = Colors.green;
      statusIcon = Icons.phone_in_talk;
    } else if (_consultationCallState == CallStateEnum.PROGRESS) {
      statusColor = Colors.orange;
      statusIcon = Icons.ring_volume;
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(statusIcon, size: 80, color: statusColor),
        SizedBox(height: 24),
        Text(
          'Attended Transfer',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 8),
        Text(
          _statusMessage,
          style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          textAlign: TextAlign.center,
        ),
        if (_consultationCallState == CallStateEnum.CONFIRMED ||
            _consultationCallState == CallStateEnum.ACCEPTED) ...[
          SizedBox(height: 8),
          ValueListenableBuilder<String>(
            valueListenable: _timeLabel,
            builder: (context, value, child) {
              return Text(
                value,
                style: TextStyle(fontSize: 14, color: Colors.grey),
              );
            },
          ),
        ],
        SizedBox(height: 16),
        _buildCallInfoCard('Original Call (On Hold)',
            originalCall.remote_identity ?? 'Unknown'),
        SizedBox(height: 8),
        _buildCallInfoCard('Consultation Call', targetUri),
        if (_errorMessage != null) ...[
          SizedBox(height: 16),
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red[200]!),
            ),
            child: Row(
              children: [
                Icon(Icons.warning, color: Colors.red),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(color: Colors.red[700]),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCallInfoCard(String label, String identity) {
    return Card(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.person, color: Colors.grey),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  Text(
                    identity,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    final bool isConsultationConnected =
        _consultationCallState == CallStateEnum.CONFIRMED ||
            _consultationCallState == CallStateEnum.ACCEPTED;

    if (_transferComplete) {
      return SizedBox.shrink();
    }

    return Padding(
      padding: EdgeInsets.all(24),
      child: Column(
        children: [
          // Show loading while waiting for consultation call to connect
          if (!isConsultationConnected &&
              !_isTransferring &&
              _errorMessage == null) ...[
            CircularProgressIndicator(),
            SizedBox(height: 16),
          ],

          // Show transfer in progress
          if (_isTransferring) ...[
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Transfer in progress...'),
          ],

          // Complete Transfer Button - only when consultation is connected
          if (isConsultationConnected && !_isTransferring) ...[
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _completeTransfer,
                icon: Icon(Icons.check_circle),
                label: Text('Confirm Transfer'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            SizedBox(height: 16),
          ],

          // Cancel Transfer & Back to Call Button - always visible except during transfer
          if (!_isTransferring)
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _cancelTransfer,
                icon: Icon(Icons.call_end),
                label: Text('Cancel Transfer & Back to Call'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (!_transferComplete && !_isTransferring) {
          _cancelTransfer();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Attended Transfer'),
          automaticallyImplyLeading: false,
          actions: [
            if (!_isTransferring && !_transferComplete)
              IconButton(
                icon: Icon(Icons.close),
                onPressed: _cancelTransfer,
              ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: _buildStatusSection(),
                ),
              ),
              _buildActionButtons(),
            ],
          ),
        ),
      ),
    );
  }
}

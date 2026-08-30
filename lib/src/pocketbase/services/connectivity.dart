import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:logging/logging.dart';

/// A service that monitors the device's network connectivity status.
///
/// This service uses a hybrid approach combining:
/// 1. `internet_connection_checker_plus` for monitoring internet connectivity
/// 2. Request-based detection: actual network request success/failure
///
/// This is a singleton because we only need one global listener for internet access.
/// Each `$PocketBase` client manages its own subscription
/// to this singleton's [statusStream].
class ConnectivityService {
  ConnectivityService._() {
    _logger = Logger('ConnectivityService');
    if (enableInternetChecker && !kIsWeb) {
      _subscription =
          InternetConnection().onStatusChange.listen(_onPlatformStatusChange);
    }
  }

  // Singleton instance - lives for the app's lifetime
  static final ConnectivityService _instance = ConnectivityService._();

  /// Factory constructor returns the singleton instance.
  factory ConnectivityService() => _instance;

  /// Global flag to disable the internet checker periodic timers.
  /// Used primarily for testing.
  @visibleForTesting
  static bool enableInternetChecker = true;

  final _statusController = StreamController<bool>.broadcast();
  StreamSubscription<InternetStatus>? _subscription;
  late final Logger _logger;

  /// Counter for consecutive network failures.
  int _consecutiveFailures = 0;

  /// Number of consecutive failures before marking as offline.
  static const _failureThreshold = 2;

  /// A stream that emits `true` if the device is connected to a network,
  /// and `false` otherwise. New listeners will immediately receive the current status.
  Stream<bool> get statusStream {
    // Emit the current status to new listeners immediately.
    Timer.run(() {
      if (!_statusController.isClosed) {
        _statusController.add(isConnected);
      }
    });
    return _statusController.stream;
  }

  /// The current network connectivity status.
  bool isConnected = true;

  /// Whether the platform reports a network interface is available.
  bool _platformReportsConnected = true;

  /// Whether a network request should be attempted.
  ///
  /// Returns `true` if the platform reports a network interface is available,
  /// regardless of whether recent requests have succeeded. This allows discovery
  /// of connectivity restoration by actually trying a request.
  ///
  /// Use this to decide whether to TRY a network request.
  /// Use [isConnected] for UI display or queuing decisions.
  bool get shouldAttemptNetwork => _platformReportsConnected;

  /// Checks the current connectivity and updates the status.
  /// When called explicitly, trusts the platform status for both directions.
  Future<void> checkConnectivity() async {
    if (!enableInternetChecker || kIsWeb) return;
    final platformConnected = await InternetConnection().hasInternetAccess;

    // For explicit checks, trust the platform status
    _setConnected(platformConnected);
  }

  /// Called when the platform connectivity status changes.
  void _onPlatformStatusChange(InternetStatus status) {
    final platformConnected = status == InternetStatus.connected;
    _platformReportsConnected = platformConnected;

    if (!platformConnected) {
      // Definitely offline - no network interface
      _setConnected(false);
    }
    // Note: We don't automatically set connected=true here.
    // We wait for an actual request to succeed to confirm connectivity.
  }

  /// Report that a network request failed.
  /// After [_failureThreshold] consecutive failures, marks as offline.
  void reportNetworkFailure() {
    _consecutiveFailures++;
    _logger.fine(
        'Network failure reported ($_consecutiveFailures consecutive failures)');

    if (_consecutiveFailures >= _failureThreshold && isConnected) {
      _logger.info('Multiple network failures detected, marking as offline.');
      _setConnected(false);
    }
  }

  /// Report that a network request succeeded.
  /// This confirms connectivity is working and resets failure counter.
  void reportNetworkSuccess() {
    _consecutiveFailures = 0;

    if (!isConnected && _platformReportsConnected) {
      _logger.info('Network request succeeded - connectivity restored.');
      _setConnected(true);
    }
  }

  void _setConnected(bool value) {
    if (value != isConnected) {
      isConnected = value;
      _consecutiveFailures = 0; // Reset on any state change
      if (!_statusController.isClosed) {
        _statusController.add(isConnected);
      }
      _logger.info('Status changed: ${isConnected ? "Online" : "Offline"}');
    }
  }

  /// Resets the connectivity stream subscription.
  /// Useful when the app resumes from background or after a hot restart.
  void resetSubscription() {
    _logger.info('Resetting connectivity stream subscription.');
    _subscription?.cancel();
    if (enableInternetChecker && !kIsWeb) {
      _subscription =
          InternetConnection().onStatusChange.listen(_onPlatformStatusChange);
      checkConnectivity();
    }
  }

  /// Directly set the connectivity status. Only use for testing.
  @visibleForTesting
  void setConnectivityStatus(bool status) {
    _platformReportsConnected = status;
    _setConnected(status);
  }
}

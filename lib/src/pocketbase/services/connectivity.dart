import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:logging/logging.dart';

/// A service that monitors the device's network connectivity status.
///
/// This is a singleton because `connectivity_plus`'s `Connectivity()` is also
/// a global singleton. Disposing and recreating wrappers around it causes
/// instability in connectivity detection. Each `$PocketBase` client manages
/// its own subscription to this singleton's [statusStream].
class ConnectivityService {
  ConnectivityService._() {
    _logger = Logger('ConnectivityService');
    _subscription = Connectivity().onConnectivityChanged.listen(_updateStatus);
  }

  // Singleton instance - lives for the app's lifetime
  static final ConnectivityService _instance = ConnectivityService._();

  /// Factory constructor returns the singleton instance.
  factory ConnectivityService() => _instance;

  final _statusController = StreamController<bool>.broadcast();
  late StreamSubscription<List<ConnectivityResult>> _subscription;
  late final Logger _logger;

  /// A stream that emits `true` if the device is connected to a network,
  /// and `false` otherwise. New listeners will immediately receive the current status.
  Stream<bool> get statusStream {
    // Emit the current status to new listeners immediately.
    // Using Timer.run to ensure it's added asynchronously in the next microtask,
    // allowing the listener to be fully set up.
    Timer.run(() {
      if (!_statusController.isClosed) {
        _statusController.add(isConnected);
      }
    });
    return _statusController.stream;
  }

  /// The current network connectivity status.
  bool isConnected = true;

  /// Checks the current connectivity and updates the status.
  Future<void> checkConnectivity() async {
    final result = await Connectivity().checkConnectivity();
    _updateStatus(result);
  }

  void _updateStatus(List<ConnectivityResult> result) {
    // We consider the device connected if it's not 'none'.
    final newStatus = !result.contains(ConnectivityResult.none);
    if (newStatus != isConnected) {
      isConnected = newStatus;
      if (!_statusController.isClosed) {
        _statusController.add(isConnected);
      }
      _logger.info('Status changed: ${isConnected ? "Online" : "Offline"}');
    }
  }

  /// Resets the connectivity stream subscription.
  /// Useful when the app resumes from background or after a hot restart
  /// to ensure the stream is not stale.
  void resetSubscription() {
    _logger.info('Resetting connectivity stream subscription.');
    _subscription.cancel();
    _subscription = Connectivity().onConnectivityChanged.listen(_updateStatus);
  }
}

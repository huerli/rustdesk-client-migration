import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Lines emitted by the core while a connection is being established, shown on
/// the "Connecting..." dialog so the transport race can be followed without
/// reading the log file.
class ConnectionLogModel with ChangeNotifier {
  /// A long round can retry for a while; keep the tail only.
  static const _maxLines = 200;

  final List<String> _lines = [];
  final Stopwatch _clock = Stopwatch();

  List<String> get lines => _lines;

  bool get isEmpty => _lines.isEmpty;

  void clear() {
    _lines.clear();
    _clock
      ..reset()
      ..start();
    notifyListeners();
  }

  void add(String line) {
    if (line.isEmpty) return;
    if (!_clock.isRunning) _clock.start();
    final elapsed = (_clock.elapsedMilliseconds / 1000).toStringAsFixed(1);
    _lines.add('+${elapsed}s  $line');
    if (_lines.length > _maxLines) {
      _lines.removeRange(0, _lines.length - _maxLines);
    }
    notifyListeners();
  }
}

/// Scrolling tail of [ConnectionLogModel]. Collapses while empty so the
/// connecting dialog keeps its normal size until the first line lands.
class ConnectionLogView extends StatelessWidget {
  const ConnectionLogView(this.model, {Key? key}) : super(key: key);

  final ConnectionLogModel model;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: model,
      child: Consumer<ConnectionLogModel>(
        builder: (context, model, child) => model.isEmpty
            ? const SizedBox.shrink()
            : Container(
                width: 440,
                constraints: const BoxConstraints(maxHeight: 148),
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  border: Border.all(
                      color: Theme.of(context).dividerColor, width: 1),
                  borderRadius: BorderRadius.circular(4),
                ),
                // Newest at the bottom, anchored there: a log tail that keeps
                // following the connection without a scroll controller.
                child: ListView.builder(
                  reverse: true,
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: model.lines.length,
                  itemBuilder: (context, index) => Text(
                    model.lines[model.lines.length - 1 - index],
                    maxLines: 3,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.4,
                      fontFamily:
                          defaultTargetPlatform == TargetPlatform.windows
                              ? 'Consolas'
                              : 'monospace',
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

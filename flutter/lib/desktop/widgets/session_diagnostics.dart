import 'package:flutter/material.dart';

import '../../common.dart';
import '../../common/widgets/overlay.dart';
import '../../models/model.dart';

class DesktopQualityMonitor extends StatelessWidget {
  final QualityMonitorModel model;

  const DesktopQualityMonitor({super.key, required this.model});

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [QualityMonitor(model)],
            ),
          ),
        ),
      );
}

class SessionDiagnosticsButton extends StatelessWidget {
  final FFI ffi;
  final String connection;
  final Duration Function() connectedDuration;

  const SessionDiagnosticsButton({
    super.key,
    required this.ffi,
    required this.connection,
    required this.connectedDuration,
  });

  @override
  Widget build(BuildContext context) {
    final model = ffi.qualityMonitorModel;
    final showDuration = MediaQuery.sizeOf(context).width >= 480;
    return MenuAnchor(
      consumeOutsideTap: true,
      crossAxisUnconstrained: false,
      alignmentOffset: const Offset(0, 3),
      style: const MenuStyle(
        alignment: AlignmentDirectional.bottomStart,
        padding: WidgetStatePropertyAll(EdgeInsets.zero),
      ),
      menuChildren: [
        ListenableBuilder(
          listenable: model,
          builder: (context, _) => _SessionDetails(
            data: model.data,
            peer: ffi.ffiModel.pi,
            connection: connection,
          ),
        ),
      ],
      builder: (context, controller, _) => Tooltip(
        message: translate('Network'),
        child: TextButton(
          style: TextButton.styleFrom(
            minimumSize: const Size(28, 24),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: () =>
              controller.isOpen ? controller.close() : controller.open(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.network_check, size: 16),
              if (showDuration) ...[
                const SizedBox(width: 4),
                ListenableBuilder(
                  listenable: model,
                  builder: (context, _) => Text(
                    formatDurationToTime(connectedDuration()),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SessionDetails extends StatelessWidget {
  final QualityMonitorData data;
  final PeerInfo peer;
  final String connection;

  const _SessionDetails({
    required this.data,
    required this.peer,
    required this.connection,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final delay = int.tryParse(data.delay ?? '');
    final resolution = peer
        .getCurDisplays()
        .map((display) => '${display.width} × ${display.height}')
        .join(' / ');
    return SizedBox(
      width: 286,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.network_check,
                    size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(translate('Network'),
                      style: theme.textTheme.titleSmall),
                ),
                Text(delay == null || delay <= 0 ? '—' : '$delay ms',
                    style: theme.textTheme.titleSmall),
              ],
            ),
            const Divider(),
            _row(context, translate('FPS'), data.fps),
            _row(context, translate('Speed'), data.speed),
            _row(
                context,
                translate('Bitrate'),
                data.targetBitrate == null
                    ? null
                    : '${data.targetBitrate} kb/s'),
            const Divider(),
            _row(context, translate('Connection'), connection),
            _row(context, translate('Version'), peer.version),
            _row(context, translate('Platform'), peer.platform),
            const Divider(),
            _row(context, translate('Codec'), data.codecFormat),
            _row(context, translate('Resolution'), resolution),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String label, String? value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(label,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Text(value == null || value.isEmpty ? '—' : value,
                style: theme.textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../common.dart';
import '../../common/formatter/id_formatter.dart';
import '../../models/peer_model.dart';

class DeviceListRow extends StatelessWidget {
  const DeviceListRow({
    super.key,
    required this.peer,
    required this.actions,
    this.selected = false,
    this.hideUsername = false,
    this.note = '',
    this.onConnect,
  });

  final Peer peer;
  final Widget actions;
  final bool selected;
  final bool hideUsername;
  final String note;
  final VoidCallback? onConnect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final name = peer.alias.isNotEmpty
        ? peer.alias
        : (peer.hostname.isNotEmpty ? peer.hostname : formatID(peer.id));
    final details = [
      formatID(peer.id),
      if (!hideUsername && peer.username.isNotEmpty) peer.username,
      if (note.isNotEmpty) note,
    ].join(' · ');
    final status = translate(peer.online ? 'Online' : 'Offline');
    final statusColor = peer.online
        ? const Color(0xFF2BA66A)
        : theme.colorScheme.onSurface.withOpacity(0.4);

    return LayoutBuilder(builder: (context, constraints) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color:
              selected ? primary.withOpacity(0.06) : theme.colorScheme.surface,
          border: Border.all(
            color: selected ? primary.withOpacity(0.4) : theme.dividerColor,
          ),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: primary.withOpacity(0.09),
                borderRadius: BorderRadius.circular(10),
              ),
              child: ColorFiltered(
                colorFilter: ColorFilter.mode(primary, BlendMode.srcIn),
                child: getPlatformImage(peer.platform, size: 22),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 5),
                  Text(details,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color:
                              theme.colorScheme.onSurface.withOpacity(0.55))),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Tooltip(
              message: status,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration:
                      BoxDecoration(color: statusColor, shape: BoxShape.circle),
                ),
                if (constraints.maxWidth >= 440) ...[
                  const SizedBox(width: 7),
                  Text(status,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: statusColor)),
                ],
              ]),
            ),
            if (onConnect != null) ...[
              const SizedBox(width: 10),
              IconButton(
                tooltip: translate('Connect'),
                onPressed: onConnect,
                icon: Icon(Icons.login_rounded, size: 19, color: primary),
              ),
            ],
            actions,
          ],
        ),
      );
    });
  }
}

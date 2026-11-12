// main window right pane

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/connection_page_title.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/widgets/popup_menu.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_hbb/models/peer_model.dart';

import '../../common.dart';
import '../../common/formatter/id_formatter.dart';
import '../../common/widgets/peer_tab_page.dart';
import '../../common/widgets/autocomplete.dart';
import '../../common/widgets/request_approval_menu.dart';
import '../../models/platform_model.dart';
import '../../desktop/widgets/material_mod_popup_menu.dart' as mod_menu;

class OnlineStatusWidget extends StatefulWidget {
  const OnlineStatusWidget({Key? key, this.onSvcStatusChanged})
      : super(key: key);

  final VoidCallback? onSvcStatusChanged;

  @override
  State<OnlineStatusWidget> createState() => _OnlineStatusWidgetState();
}

/// State for the connection page.
class _OnlineStatusWidgetState extends State<OnlineStatusWidget> {
  final _svcStopped = Get.find<RxBool>(tag: 'stop-service');
  final _svcIsUsingPublicServer = true.obs;
  Timer? _updateTimer;

  double get em => 14.0;
  double? get height => bind.isIncomingOnly() ? null : em * 3;

  void onUsePublicServerGuide() {
    const url = "https://rustdesk.com/pricing";
    canLaunchUrlString(url).then((can) {
      if (can) {
        launchUrlString(url);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _updateTimer = periodic_immediate(Duration(seconds: 1), () async {
      updateStatus();
    });
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isIncomingOnly = bind.isIncomingOnly();
    startServiceWidget() => Offstage(
          offstage: !_svcStopped.value,
          child: InkWell(
                  onTap: () async {
                    await start_service(true);
                  },
                  child: Text(translate("Start service"),
                      style: TextStyle(
                          decoration: TextDecoration.underline, fontSize: em)))
              .marginOnly(left: em),
        );

    setupServerWidget() => Flexible(
          child: Offstage(
            offstage: !(!_svcStopped.value &&
                stateGlobal.svcStatus.value == SvcStatus.ready &&
                _svcIsUsingPublicServer.value),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(', ', style: TextStyle(fontSize: em)),
                Flexible(
                  child: InkWell(
                    onTap: onUsePublicServerGuide,
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            translate('setup_server_tip'),
                            style: TextStyle(
                                decoration: TextDecoration.underline,
                                fontSize: em),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              ],
            ),
          ),
        );

    final statusColor = _svcStopped.value ||
            stateGlobal.svcStatus.value == SvcStatus.connecting
        ? kColorWarn
        : (stateGlobal.svcStatus.value == SvcStatus.ready
            ? Color.fromARGB(255, 50, 190, 166)
            : Color.fromARGB(255, 224, 79, 95));

    basicWidget() => Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 8,
                    width: 8,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: statusColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildConnStatusMsg(),
                ],
              ),
            ),
            // stop
            if (!isIncomingOnly) startServiceWidget(),
            // ready && public
            // No need to show the guide if is custom client.
            if (!isIncomingOnly) setupServerWidget(),
          ],
        );

    return Container(
      height: height,
      child: Obx(() => isIncomingOnly
          ? Column(
              children: [
                basicWidget(),
                Align(
                        child: startServiceWidget(),
                        alignment: Alignment.centerLeft)
                    .marginOnly(top: 2.0, left: 22.0),
              ],
            )
          : basicWidget()),
    ).paddingOnly(right: isIncomingOnly ? 8 : 0);
  }

  _buildConnStatusMsg() {
    widget.onSvcStatusChanged?.call();
    return Text(
      _svcStopped.value
          ? translate("Service is not running")
          : stateGlobal.svcStatus.value == SvcStatus.connecting
              ? translate("connecting_status")
              : stateGlobal.svcStatus.value == SvcStatus.notReady
                  ? translate("not_ready_status")
                  : translate('Ready'),
      style: TextStyle(fontSize: em),
    );
  }

  updateStatus() async {
    final status =
        jsonDecode(await bind.mainGetConnectStatus()) as Map<String, dynamic>;
    final statusNum = status['status_num'] as int;
    if (statusNum == 0) {
      stateGlobal.svcStatus.value = SvcStatus.connecting;
    } else if (statusNum == -1) {
      stateGlobal.svcStatus.value = SvcStatus.notReady;
    } else if (statusNum == 1) {
      stateGlobal.svcStatus.value = SvcStatus.ready;
    } else {
      stateGlobal.svcStatus.value = SvcStatus.notReady;
    }
    _svcIsUsingPublicServer.value = await bind.mainIsUsingPublicServer();
    try {
      stateGlobal.videoConnCount.value = status['video_conn_count'] as int;
    } catch (_) {}
  }
}

class _HeroAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _HeroAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 20,
              color: theme.colorScheme.onSurface.withOpacity(0.75),
            ),
            const SizedBox(width: 9),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 22,
      child: VerticalDivider(
        width: 1,
        color: Theme.of(context).brightness == Brightness.dark
            ? MyTheme.borderDark
            : MyTheme.borderLight,
      ),
    );
  }
}

Future<String?> _askRemoteId(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (dialogContext) {
      var id = '';
      void submit() {
        final value = trimID(id);
        if (value.isNotEmpty) {
          Navigator.of(dialogContext).pop(value);
        }
      }

      return AlertDialog(
        contentPadding: EdgeInsets.zero,
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  translate('Connect'),
                  style: Theme.of(dialogContext).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  translate('Enter Remote ID'),
                  style: Theme.of(dialogContext).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                TextField(
                  autofocus: true,
                  textInputAction: TextInputAction.go,
                  inputFormatters: [IDTextInputFormatter()],
                  decoration: InputDecoration(
                    hintText: translate('Enter Remote ID'),
                    prefixIcon: const Icon(Icons.numbers_rounded, size: 20),
                  ),
                  onChanged: (value) => id = value,
                  onSubmitted: (_) => submit(),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: Text(translate('Cancel')),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: submit,
                      child: Text(translate('Connect')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// Connection page for connecting to a remote peer.
class ConnectionPage extends StatefulWidget {
  final Peer? selectedPeer;
  final bool showAllDevices;

  const ConnectionPage({Key? key, this.selectedPeer, this.showAllDevices = false})
      : super(key: key);

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

/// State for the connection page.
class _ConnectionPageState extends State<ConnectionPage>
    with SingleTickerProviderStateMixin, WindowListener {
  /// Controller for the id input bar.
  final _idController = IDTextEditingController();

  final RxBool _idInputFocused = false.obs;
  final FocusNode _idFocusNode = FocusNode();
  final TextEditingController _idEditingController = TextEditingController();

  String selectedConnectionType = 'Connect';

  bool isWindowMinimized = false;

  final AllPeersLoader _allPeersLoader = AllPeersLoader();

  // https://github.com/flutter/flutter/issues/157244
  Iterable<Peer> _autocompleteOpts = [];

  final _menuOpen = false.obs;
  final _heroHovered = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    _allPeersLoader.init(setState);
    _idFocusNode.addListener(onFocusChanged);
    if (widget.selectedPeer != null) {
      _idController.id = widget.selectedPeer!.id;
    } else if (_idController.text.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final lastRemoteId = await bind.mainGetLastRemoteId();
        if (lastRemoteId != _idController.id) {
          setState(() {
            _idController.id = lastRemoteId;
          });
        }
      });
    }
    Get.put<TextEditingController>(_idEditingController);
    Get.put<IDTextEditingController>(_idController);
    windowManager.addListener(this);
  }

  @override
  void didUpdateWidget(covariant ConnectionPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedPeer?.id != oldWidget.selectedPeer?.id &&
        widget.selectedPeer != null) {
      _idController.id = widget.selectedPeer!.id;
    }
  }

  @override
  void dispose() {
    _heroHovered.dispose();
    _idController.dispose();
    windowManager.removeListener(this);
    _allPeersLoader.clear();
    _idFocusNode.removeListener(onFocusChanged);
    _idFocusNode.dispose();
    _idEditingController.dispose();
    if (Get.isRegistered<IDTextEditingController>()) {
      Get.delete<IDTextEditingController>();
    }
    if (Get.isRegistered<TextEditingController>()) {
      Get.delete<TextEditingController>();
    }
    super.dispose();
  }

  @override
  void onWindowEvent(String eventName) {
    super.onWindowEvent(eventName);
    if (eventName == 'minimize') {
      isWindowMinimized = true;
    } else if (eventName == 'maximize' || eventName == 'restore') {
      if (isWindowMinimized && isWindows) {
        // windows can't update when minimized.
        Get.forceAppUpdate();
      }
      isWindowMinimized = false;
    }
  }

  @override
  void onWindowEnterFullScreen() {
    // Remove edge border by setting the value to zero.
    stateGlobal.resizeEdgeSize.value = 0;
  }

  @override
  void onWindowLeaveFullScreen() {
    // Restore edge border to default edge size.
    stateGlobal.resizeEdgeSize.value = stateGlobal.isMaximized.isTrue
        ? kMaximizeEdgeSize
        : windowResizeEdgeSize;
  }

  @override
  void onWindowClose() {
    super.onWindowClose();
    bind.mainOnMainWindowClose();
  }

  void onFocusChanged() {
    _idInputFocused.value = _idFocusNode.hasFocus;
    if (_idFocusNode.hasFocus) {
      if (_allPeersLoader.needLoad) {
        _allPeersLoader.getAllPeers();
      }

      final textLength = _idEditingController.value.text.length;
      // Select all to facilitate removing text, just following the behavior of address input of chrome.
      _idEditingController.selection =
          TextSelection(baseOffset: 0, extentOffset: textLength);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOutgoingOnly = bind.isOutgoingOnly();
    return Column(
      children: [
        _buildWorkspaceHeader(context),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final horizontalPadding =
                  (constraints.maxWidth * 0.06).clamp(24.0, 80.0).toDouble();
              final heroHeight =
                  ((constraints.maxWidth - horizontalPadding * 2) / 2.5)
                      .clamp(160.0, 440.0).toDouble();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.showAllDevices)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                        child: PeerTabPage(),
                      ),
                    )
                  else
                    Expanded(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(
                            horizontalPadding, 32, horizontalPadding, 32),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              height: heroHeight + 64,
                              child: MouseRegion(
                                onEnter: (_) => _heroHovered.value = true,
                                onExit: (_) => _heroHovered.value = false,
                                child: _buildHeroCard(context, heroHeight),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (!isOutgoingOnly) const Divider(height: 1),
                  if (!isOutgoingOnly)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: OnlineStatusWidget(),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildWorkspaceHeader(BuildContext context) {
    if (widget.showAllDevices) return _buildDeviceListHeader(context);
    final theme = Theme.of(context);
    final peer = widget.selectedPeer;
    final online = peer?.online ?? true;
    final name = peer == null
        ? Platform.localHostname
        : (peer.hostname.isNotEmpty
            ? peer.hostname
            : (peer.alias.isNotEmpty ? peer.alias : peer.id));
    return Container(
      height: 64,
      padding: const EdgeInsets.fromLTRB(28, 0, 20, 0),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.brightness == Brightness.dark
                ? MyTheme.borderDark
                : MyTheme.borderLight,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF111315),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: online
                        ? const Color(0xFF35B66A)
                        : const Color(0xFF9CA3AF),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  online
                      ? translate('Online')
                      : translate('Offline'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Row(children: [
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: translate('More'),
                icon: Icon(
                  Icons.more_vert,
                  size: 21,
                  color: theme.colorScheme.onSurface.withOpacity(0.72),
                ),
                onSelected: (value) {
                  switch (value) {
                    case 'file':
                      onConnect(isFileTransfer: true);
                      break;
                    case 'camera':
                      onConnect(isViewCamera: true);
                      break;
                    case 'terminal':
                      onConnect(isTerminal: true);
                      break;
                    case 'tunnel':
                      onConnect(isTcpTunneling: true);
                      break;
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'file',
                    child: Text(translate('Transfer file')),
                  ),
                  PopupMenuItem(
                    value: 'camera',
                    child: Text(translate('View camera')),
                  ),
                  PopupMenuItem(
                    value: 'terminal',
                    child: Text(translate('Terminal')),
                  ),
                  PopupMenuItem(
                    value: 'tunnel',
                    child: Text(translate('TCP tunneling')),
                  ),
                ],
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceListHeader(BuildContext context) {
    final theme = Theme.of(context);
    final model = gFFI.peerTabModel;
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) => Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 28),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(bottom: BorderSide(color: theme.dividerColor)),
        ),
        child: Row(children: [
          Icon(Icons.devices_outlined,
              size: 23, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              model.currentTab == 0
                  ? translate('All devices')
                  : model.tabTooltip(model.currentTab),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontSize: 22, fontWeight: FontWeight.w700),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildHeroCard(BuildContext context, double heroHeight) {
    final theme = Theme.of(context);
    final peer = widget.selectedPeer;
    final hasPeer = peer != null;
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: theme.brightness == Brightness.dark
              ? MyTheme.borderDark
              : MyTheme.borderLight,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Column(
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRect(
                    child: ValueListenableBuilder<bool>(
                      valueListenable: _heroHovered,
                      builder: (context, hovered, child) =>
                          TweenAnimationBuilder<double>(
                        duration: const Duration(milliseconds: 160),
                        curve: Curves.easeOut,
                        tween: Tween(end: hovered ? 4.0 : 0.0),
                        child: child,
                        builder: (context, blur, child) => ImageFiltered(
                          enabled: blur > 0,
                          imageFilter: ImageFilter.blur(
                            sigmaX: blur,
                            sigmaY: blur,
                            tileMode: TileMode.clamp,
                          ),
                          child: child,
                        ),
                      ),
                      child: Image.asset(
                        'assets/desktop_workspace_wallpaper.png',
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.medium,
                      ),
                    ),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.08),
                        ],
                      ),
                    ),
                  ),
                  Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      mouseCursor: SystemMouseCursors.click,
                      hoverColor: Colors.transparent,
                      highlightColor: Colors.white.withOpacity(0.2),
                      onTap: () {
                        if (hasPeer) {
                          onConnect();
                        } else {
                          _showConnectPanel();
                        }
                      },
                      child: Align(
                        alignment: const Alignment(0, 0.8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 10,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                translate('Enter desktop'),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w500,
                                  shadows: [Shadow(blurRadius: 8, color: Colors.black38)],
                                ),
                              ),
                              const SizedBox(width: 10),
                              const Icon(
                                Icons.arrow_forward_rounded,
                                color: Colors.white,
                                size: 24,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              height: 64,
              color: theme.colorScheme.surface,
              child: Row(
                children: [
                  _HeroAction(
                    icon: Icons.folder_copy_outlined,
                    label: translate('Transfer file'),
                    onTap: () => onConnect(isFileTransfer: true),
                  ),
                  _HeroDivider(),
                  _HeroAction(
                    icon: Icons.videocam_outlined,
                    label: translate('View camera'),
                    onTap: () => onConnect(isViewCamera: true),
                  ),
                  _HeroDivider(),
                  _HeroAction(
                    icon: Icons.terminal_rounded,
                    label: translate('Terminal'),
                    onTap: () => onConnect(isTerminal: true),
                  ),
                  _HeroDivider(),
                  _HeroAction(
                    icon: Icons.settings_ethernet_rounded,
                    label: translate('TCP tunneling'),
                    onTap: () => onConnect(isTcpTunneling: true),
                  ),
                  _HeroDivider(),
                  SizedBox(
                    width: 62,
                    child: Tooltip(
                      message: translate('More'),
                      child: InkWell(
                        onTap: _showMoreTools,
                        child: const Center(
                          child: Icon(Icons.grid_view_outlined, size: 22),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showMoreTools() {
    final peer = widget.selectedPeer;
    Peer? lanPeer;
    if (peer != null) {
      for (final lan in gFFI.lanPeersModel.peers) {
        if (lan.id == peer.id || lan.ipAddresses.split(',').contains(peer.id)) {
          lanPeer = lan;
          break;
        }
      }
    }
    final wakeId = lanPeer?.id;

    Future<void> startTool({
      bool isFileTransfer = false,
      bool isViewCamera = false,
      bool isTerminal = false,
      bool isTcpTunneling = false,
    }) async {
      final id = peer?.id ?? await _askRemoteId(context);
      if (!mounted || id == null) return;
      await connect(context, id,
          isFileTransfer: isFileTransfer,
          isViewCamera: isViewCamera,
          isTerminal: isTerminal,
          isTcpTunneling: isTcpTunneling);
    }

    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        Widget tool(IconData icon, String label, VoidCallback? action) {
          return Material(
            color: action == null
                ? theme.colorScheme.surface
                : Color.alphaBlend(
                    MyTheme.accent.withOpacity(0.045),
                    theme.colorScheme.surface,
                  ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(5),
              side: BorderSide(color: theme.dividerColor),
            ),
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              minTileHeight: 54,
              leading: Icon(icon),
              title: Text(translate(label)),
              trailing: const Icon(Icons.chevron_right, size: 18),
              enabled: action != null,
              onTap: action == null
                  ? null
                  : () {
                      Navigator.pop(dialogContext);
                      action();
                    },
            ),
          );
        }

        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          titlePadding: EdgeInsets.zero,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
                child: Text(translate('More')),
              ),
              const Divider(height: 1),
            ],
          ),
          content: SizedBox(
            width: 448,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  tool(Icons.folder_copy_outlined, 'Transfer file',
                      () => startTool(isFileTransfer: true)),
                  const SizedBox(height: 5),
                  tool(Icons.videocam_outlined, 'View camera',
                      () => startTool(isViewCamera: true)),
                  const SizedBox(height: 5),
                  tool(Icons.terminal_rounded, 'Terminal',
                      () => startTool(isTerminal: true)),
                  if (isDesktop) ...[
                    const SizedBox(height: 5),
                    tool(Icons.settings_ethernet_rounded, 'TCP tunneling',
                        () => startTool(isTcpTunneling: true)),
                    const SizedBox(height: 5),
                    tool(Icons.power_settings_new, 'WOL',
                        wakeId == null ? null : () => bind.mainWol(id: wakeId)),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            SizedBox(
              width: 210,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(translate('Close')),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Callback for the connect button.
  /// Connects to the selected peer.
  void onConnect(
      {bool isFileTransfer = false,
      bool isViewCamera = false,
      bool isTerminal = false,
      bool isTcpTunneling = false}) {
    var id = _idController.id;
    if (id.trim().isEmpty) {
      _showConnectPanel();
      return;
    }
    connect(context, id,
        isFileTransfer: isFileTransfer,
        isViewCamera: isViewCamera,
        isTerminal: isTerminal,
        isTcpTunneling: isTcpTunneling);
  }

  Future<void> _showConnectPanel() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          contentPadding: EdgeInsets.zero,
          content: _buildRemoteIDTextField(dialogContext),
        );
      },
    );
  }

  RequestApprovalMenu _requestApprovalMenu(BuildContext context) {
    MenuEntryButton<String> action(String title,
            {bool isFileTransfer = false,
            bool isViewCamera = false,
            bool isTerminal = false,
            bool isTcpTunneling = false}) =>
        MenuEntryButton<String>(
          childBuilder: (style) => Text(translate(title), style: style),
          proc: () => connect(context, _idController.id,
              loginMethod: 'request-approval',
              isFileTransfer: isFileTransfer,
              isViewCamera: isViewCamera,
              isTerminal: isTerminal,
              isTcpTunneling: isTcpTunneling),
          padding: EdgeInsets.symmetric(horizontal: kDesktopMenuPadding.left),
          dismissOnClicked: true,
        );

    return RequestApprovalMenu(
      title: translate('Request approval'),
      padding: EdgeInsets.symmetric(horizontal: kDesktopMenuPadding.left),
      arrowScale: MenuConfig.iconScale,
      entries: [
        action('Connect'),
        action('Transfer file', isFileTransfer: true),
        action('View camera', isViewCamera: true),
        action('${translate('Terminal')} (beta)', isTerminal: true),
        if (isDesktop) action('TCP tunneling', isTcpTunneling: true),
      ],
    );
  }

  /// UI for the remote ID TextField.
  /// Search for a peer.
  Widget _buildRemoteIDTextField(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    var w = Container(
      width: 440,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.all(Radius.circular(18)),
        border: Border.all(
          color: isDark ? MyTheme.borderDark : MyTheme.borderLight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.05),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            getConnectionPageTitle(context, false).marginOnly(bottom: 16),
            Row(
              children: [
                Expanded(
                    child: RawAutocomplete<Peer>(
                  optionsBuilder: (TextEditingValue textEditingValue) {
                    if (textEditingValue.text == '') {
                      _autocompleteOpts = const Iterable<Peer>.empty();
                    } else if (_allPeersLoader.peers.isEmpty &&
                        !_allPeersLoader.isPeersLoaded) {
                      Peer emptyPeer = Peer(
                        id: '',
                        username: '',
                        hostname: '',
                        alias: '',
                        platform: '',
                        tags: [],
                        hash: '',
                        password: '',
                        forceAlwaysRelay: false,
                        rdpPort: '',
                        rdpUsername: '',
                        loginName: '',
                        device_group_name: '',
                        note: '',
                      );
                      _autocompleteOpts = [emptyPeer];
                    } else {
                      String textWithoutSpaces =
                          textEditingValue.text.replaceAll(" ", "");
                      if (int.tryParse(textWithoutSpaces) != null) {
                        textEditingValue = TextEditingValue(
                          text: textWithoutSpaces,
                          selection: textEditingValue.selection,
                        );
                      }
                      String textToFind = textEditingValue.text.toLowerCase();
                      _autocompleteOpts = _allPeersLoader.peers
                          .where((peer) =>
                              peer.id.toLowerCase().contains(textToFind) ||
                              peer.username
                                  .toLowerCase()
                                  .contains(textToFind) ||
                              peer.hostname
                                  .toLowerCase()
                                  .contains(textToFind) ||
                              peer.alias.toLowerCase().contains(textToFind))
                          .toList();
                      _allPeersLoader.queryOnlines(_autocompleteOpts);
                    }
                    return _autocompleteOpts;
                  },
                  focusNode: _idFocusNode,
                  textEditingController: _idEditingController,
                  fieldViewBuilder: (
                    BuildContext context,
                    TextEditingController fieldTextEditingController,
                    FocusNode fieldFocusNode,
                    VoidCallback onFieldSubmitted,
                  ) {
                    updateTextAndPreserveSelection(
                        fieldTextEditingController, _idController.text);
                    return Obx(() => TextField(
                          autocorrect: false,
                          enableSuggestions: false,
                          keyboardType: TextInputType.visiblePassword,
                          focusNode: fieldFocusNode,
                          style: const TextStyle(
                            fontFamily: 'WorkSans',
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                          ),
                          maxLines: 1,
                          cursorColor:
                              Theme.of(context).textTheme.titleLarge?.color,
                          decoration: InputDecoration(
                              filled: true,
                              counterText: '',
                              hintText: _idInputFocused.value
                                  ? null
                                  : translate('Enter Remote ID'),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 13)),
                          controller: fieldTextEditingController,
                          inputFormatters: [IDTextInputFormatter()],
                          onChanged: (v) {
                            _idController.id = v;
                          },
                          onSubmitted: (_) {
                            onConnect();
                          },
                        ).workaroundFreezeLinuxMint());
                  },
                  onSelected: (option) {
                    setState(() {
                      _idController.id = option.id;
                      FocusScope.of(context).unfocus();
                    });
                  },
                  optionsViewBuilder: (BuildContext context,
                      AutocompleteOnSelected<Peer> onSelected,
                      Iterable<Peer> options) {
                    options = _autocompleteOpts;
                    double maxHeight = options.length * 50;
                    if (options.length == 1) {
                      maxHeight = 52;
                    } else if (options.length == 3) {
                      maxHeight = 146;
                    } else if (options.length == 4) {
                      maxHeight = 193;
                    }
                    maxHeight = maxHeight.clamp(0, 200);

                    return Align(
                      alignment: Alignment.topLeft,
                      child: Container(
                          decoration: BoxDecoration(
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.14),
                                blurRadius: 18,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Material(
                                elevation: 8,
                                color: Theme.of(context).colorScheme.surface,
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxHeight: maxHeight,
                                    maxWidth: 390,
                                  ),
                                  child: _allPeersLoader.peers.isEmpty &&
                                          !_allPeersLoader.isPeersLoaded
                                      ? Container(
                                          height: 80,
                                          child: Center(
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          ))
                                      : Padding(
                                          padding:
                                              const EdgeInsets.only(top: 5),
                                          child: ListView(
                                            children: options
                                                .map((peer) =>
                                                    AutocompletePeerTile(
                                                        onSelect: () =>
                                                            onSelected(peer),
                                                        peer: peer))
                                                .toList(),
                                          ),
                                        ),
                                ),
                              ))),
                    );
                  },
                )),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 14.0),
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                SizedBox(
                  height: 40.0,
                  child: ElevatedButton(
                    onPressed: () {
                      onConnect();
                    },
                    child: Text(translate("Connect")),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  height: 40.0,
                  width: 40.0,
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: StatefulBuilder(
                      builder: (context, setState) {
                        var offset = Offset(0, 0);
                        return Obx(() => InkWell(
                              child: _menuOpen.value
                                  ? Transform.rotate(
                                      angle: pi,
                                      child: Icon(IconFont.more, size: 14),
                                    )
                                  : Icon(IconFont.more, size: 14),
                              onTapDown: (e) {
                                offset = e.globalPosition;
                              },
                              onTap: () async {
                                _menuOpen.value = true;
                                final x = offset.dx;
                                final y = offset.dy;
                                await mod_menu
                                    .showMenu(
                                  context: context,
                                  position: RelativeRect.fromLTRB(x, y, x, y),
                                  items: [
                                    (
                                      'Transfer file',
                                      () => onConnect(isFileTransfer: true)
                                    ),
                                    (
                                      'View camera',
                                      () => onConnect(isViewCamera: true)
                                    ),
                                    (
                                      '${translate('Terminal')} (beta)',
                                      () => onConnect(isTerminal: true)
                                    ),
                                    // `connect` routes this through the
                                    // desktop path only; the peer card gates
                                    // it the same way.
                                    if (isDesktop)
                                      (
                                        'TCP tunneling',
                                        () => onConnect(isTcpTunneling: true)
                                      ),
                                  ]
                                      .map<MenuEntryBase<String>>(
                                          (e) => MenuEntryButton<String>(
                                            childBuilder: (TextStyle? style) =>
                                                Text(
                                              translate(e.$1),
                                              style: style,
                                            ),
                                            proc: () => e.$2(),
                                            padding: EdgeInsets.symmetric(
                                                horizontal:
                                                    kDesktopMenuPadding.left),
                                            dismissOnClicked: true,
                                          ))
                                      .followedBy([
                                        MenuEntryDivider<String>(),
                                        _requestApprovalMenu(context),
                                      ])
                                      .map((e) => e.build(
                                          context,
                                          const MenuConfig(
                                              commonColor: CustomPopupMenuTheme
                                                  .commonColor,
                                              height:
                                                  CustomPopupMenuTheme.height,
                                              dividerHeight:
                                                  CustomPopupMenuTheme
                                                      .dividerHeight)))
                                      .expand((i) => i)
                                      .toList(),
                                  elevation: 8,
                                )
                                    .then((_) {
                                  _menuOpen.value = false;
                                });
                              },
                            ));
                      },
                    ),
                  ),
                ),
              ]),
            ),
          ],
        ),
    );
    return Container(
        constraints: const BoxConstraints(maxWidth: 600), child: w);
  }
}

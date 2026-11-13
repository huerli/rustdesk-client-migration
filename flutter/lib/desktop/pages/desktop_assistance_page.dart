import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../common.dart';
import '../../common/formatter/id_formatter.dart';
import '../../consts.dart';
import '../../models/platform_model.dart';
import '../../models/server_model.dart';
import 'desktop_setting_page.dart';

class DesktopAssistancePage extends StatefulWidget {
  const DesktopAssistancePage({super.key, required this.serviceStopped});

  final RxBool serviceStopped;

  @override
  State<DesktopAssistancePage> createState() => _DesktopAssistancePageState();
}

class _DesktopAssistancePageState extends State<DesktopAssistancePage> {
  final _partner = IDTextEditingController();

  @override
  void dispose() {
    _partner.dispose();
    super.dispose();
  }

  void _connect() {
    if (_partner.id.isNotEmpty) {
      connect(context, _partner.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            translate('Remote assistance'),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 18),
          if (!bind.isOutgoingOnly()) ...[
            _localDeviceCard(context, gFFI.serverModel),
            const SizedBox(height: 16),
          ],
          _partnerCard(context),
        ],
      ),
    );
  }

  Widget _localDeviceCard(BuildContext context, ServerModel model) {
    final hideStopService =
        bind.mainGetBuildinOption(key: kOptionHideStopService) == 'Y';
    final serviceFixed = isOptionFixed(kOptionStopService);
    return _card(
      context,
      title: 'Your Device',
      action: Obx(() {
        final stopped = widget.serviceStopped.value;
        return Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            Text(translate('Incoming connection')),
            if (isLinux)
              Text(translate(
                  stopped ? 'Service is not running' : 'Service is running'))
            else
              Switch(
                value: !stopped,
                activeColor: Colors.white,
                activeTrackColor: MyTheme.accent,
                onChanged: !serviceFixed && (stopped || !hideStopService)
                    ? start_service
                    : null,
              ),
          ],
        );
      }),
      content: AnimatedBuilder(
        animation: model,
        builder: (context, _) => Wrap(
          spacing: 24,
          runSpacing: 12,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ValueListenableBuilder(
              valueListenable: model.serverId,
              builder: (context, value, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(translate('ID')),
                  const SizedBox(height: 8),
                  SelectableText(
                    value.text,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
            ),
            _verification(context, model),
            ValueListenableBuilder(
              valueListenable: model.serverId,
              builder: (context, value, _) {
                final id = trimID(value.text);
                final canCopy =
                    id.isNotEmpty && value.text != translate('Generating ...');
                return OutlinedButton(
                  onPressed: canCopy
                      ? () async {
                          await Clipboard.setData(ClipboardData(text: id));
                          if (context.mounted) showToast(translate('Copied'));
                        }
                      : null,
                  child: Text(translate('Copy to clipboard')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _verification(BuildContext context, ServerModel model) {
    final method = switch (model.verificationMethod) {
      kUseTemporaryPassword => 'Use one-time password',
      kUsePermanentPassword => 'Use permanent password',
      _ => 'Use both passwords',
    };
    final clickOnly = model.approveMode == 'click';
    final label = translate(clickOnly ? 'Accept sessions via click' : method);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (bind.isDisableSettings())
          Text(label)
        else
          TextButton(
            onPressed: () =>
                DesktopSettingPage.switch2page(SettingsTabKey.safety),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: Text(label)),
                const Icon(Icons.chevron_right, size: 16),
              ],
            ),
          ),
        if (!clickOnly && model.verificationMethod != kUsePermanentPassword)
          ValueListenableBuilder(
            valueListenable: model.serverPasswd,
            builder: (context, value, _) => SelectableText(
              '${translate('One-time Password')}  ${value.text}',
            ),
          ),
      ],
    );
  }

  Widget _partnerCard(BuildContext context) {
    return _card(
      context,
      title: 'Control Remote Desktop',
      content: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(translate('Enter Remote ID')),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _partner,
                      autocorrect: false,
                      enableSuggestions: false,
                      inputFormatters: [IDTextInputFormatter()],
                      textInputAction: TextInputAction.go,
                      onSubmitted: (_) => _connect(),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: translate('Enter Remote ID'),
                        border: const OutlineInputBorder(),
                      ),
                    ).workaroundFreezeLinuxMint(),
                  ),
                  const SizedBox(width: 12),
                  ValueListenableBuilder(
                    valueListenable: _partner,
                    builder: (context, _, __) => ElevatedButton(
                      onPressed: _partner.id.isEmpty ? null : _connect,
                      child: Text(translate('Connect')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(
    BuildContext context, {
    required String title,
    required Widget content,
    Widget? action,
  }) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Wrap(
              spacing: 16,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  translate(title),
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (action != null) action,
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: content,
          ),
        ],
      ),
    );
  }
}

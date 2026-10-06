import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/providers.dart';
import '../../domain/catalog.dart';
import '../../domain/logic.dart';
import '../../domain/models.dart';
import '../../domain/rule_parser.dart';

class _Msg {
  _Msg.user(this.text) : fromUser = true, proposal = null;
  _Msg.ai(this.text, {this.proposal}) : fromUser = false;
  final bool fromUser;
  final String text;
  final _Proposal? proposal;
}

class _Proposal {
  _Proposal(this.rule, this.parsed, this.hub, this.sim);
  final Automation rule;
  final ParsedRule parsed;
  final Hub hub;
  final ({int triggers, int avgMinutes}) sim;
  bool saved = false;
}

/// Chat asisten (desain 14). Usulan aturan selalu ditampilkan JIKA/MAKA/BATAS AMAN + simulasi,
/// dan baru dikirim ke hub setelah pengguna menekan Aktifkan.
class AssistantScreen extends ConsumerStatefulWidget {
  const AssistantScreen({super.key});
  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends ConsumerState<AssistantScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _msgs = <_Msg>[];
  bool _thinking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _greet());
  }

  void _greet() {
    final site = ref.read(currentSiteProvider);
    final name = ref.read(profileProvider).value?.displayName?.split(' ').first ?? '';
    final events = site == null ? const <AppEvent>[] : ref.read(eventsProvider(site.id)).value ?? const [];
    final alarm = events.where((e) => e.type == 'alarm' && e.severity != Severity.info).firstOrNull;
    setState(() => _msgs.add(_Msg.ai(alarm == null
        ? 'Halo $name. Semua kondisi terpantau aman. Mau saya bantu buat otomasi?'
        : 'Halo $name. Ada yang perlu dicek: ${metricDef(alarm.metric ?? 'do').label.toLowerCase()} sempat ke '
            '${alarm.value == null ? '-' : formatValue(alarm.value!, alarm.metric ?? 'do')} ${metricDef(alarm.metric ?? 'do').unit}. '
            'Mau saya buatkan otomasi supaya alat menyala sendiri?')));
  }

  Future<void> _send(String text) async {
    if (text.trim().isEmpty) return;
    _input.clear();
    setState(() {
      _msgs.add(_Msg.user(text));
      _thinking = true;
    });
    _toBottom();
    await Future<void>.delayed(const Duration(milliseconds: 700));
    final reply = await _answer(text);
    if (!mounted) return;
    setState(() {
      _thinking = false;
      _msgs.add(reply);
    });
    _toBottom();
  }

  Future<_Msg> _answer(String text) async {
    final site = ref.read(currentSiteProvider);
    if (site == null) return _Msg.ai('Tambahkan usaha dan perangkat dulu, ya.');
    final hubs = ref.read(siteHubsProvider(site.id));
    final available = {for (final h in hubs) ...h.ports.values.map((p) => p.metric)};
    final t = text.toLowerCase();

    if (t.startsWith('kenapa') || t.contains('kenapa')) {
      return _Msg.ai('Dari data 7 hari, nilai paling rendah biasanya muncul pukul 03.00–05.00. Di malam hari ikan dan lumut '
          'sama-sama memakai oksigen tanpa ada fotosintesis. Saran: nyalakan aerator terjadwal 00.00–05.00.');
    }

    final parsed = parseRule(text, available: available);
    if (parsed == null) {
      return _Msg.ai('Maaf, saya belum paham. Coba sebut sensornya dan batasnya, misalnya '
          '“nyalakan aerator kalau oksigen di bawah 4”.');
    }
    for (final h in hubs) {
      final port = h.ports.entries.where((e) => e.value.metric == parsed.metric).firstOrNull?.key;
      if (port == null) continue;
      final relay = parsed.actuator == null ? null : h.relays.entries.where((e) => e.value.kind == parsed.actuator).firstOrNull?.key;
      if (parsed.actuator != null && relay == null) continue;
      final rule = Automation(
        id: 'ai_${DateTime.now().millisecondsSinceEpoch}',
        name: relay == null ? 'Kabari saat ${metricDef(parsed.metric).label.toLowerCase()} ${parsed.op == 'lt' ? 'rendah' : 'tinggi'}' : '${h.relays[relay]!.label} otomatis',
        enabled: true,
        hubId: h.id,
        trigger: ThresholdTrigger(ThresholdCond(ch: port, op: parsed.op, value: parsed.value), holdSec: 60),
        action: relay == null
            ? const NotifyAction(Severity.warning)
            : RelayAction(
                relay: relay,
                on: true,
                untilThreshold: parsed.until == null ? null : ThresholdCond(ch: port, op: parsed.op == 'lt' ? 'gt' : 'lt', value: parsed.until!)),
        maxRunSec: relay == null ? null : parsed.maxRunSec,
        cooldownSec: relay == null ? null : 600,
        source: 'ai',
        prompt: text,
      );
      final history = await ref.read(repositoryProvider).history(h.id, port, const Duration(days: 7));
      return _Msg.ai('Ini usulan aturannya. Cek dulu, lalu tekan Aktifkan kalau sudah sesuai.',
          proposal: _Proposal(rule, parsed, h, simulate(parsed, history)));
    }
    final needs = [metricDef(parsed.metric).label.toLowerCase(), if (parsed.actuator != null) actuatorDef(parsed.actuator!).label.toLowerCase()];
    return _Msg.ai('Belum ada hub yang punya ${needs.join(' dan ')} sekaligus. Pasang modulnya dulu di hub yang sama.');
  }

  Future<void> _activate(_Proposal p) async {
    final site = ref.read(currentSiteProvider)!;
    await ref.read(repositoryProvider).saveAutomation(site.id, p.rule);
    setState(() => p.saved = true);
    if (mounted) showMessage(context, 'Aturan aktif dan dikirim ke hub.');
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      });

  @override
  Widget build(BuildContext context) {
    final site = ref.watch(currentSiteProvider);
    final chips = switch (site?.kind) {
      'horticulture' => ['Siram kalau tanah di bawah 35%', 'Kabari kalau tandon di bawah 30%'],
      'livestock' => ['Nyalakan kipas kalau suhu di atas 30', 'Pemanas kalau suhu di bawah 26'],
      _ => ['Isi kolam kalau air kurang dari 70 cm', 'Nyalakan aerator kalau oksigen di bawah 4', 'Kenapa oksigen turun tiap subuh?'],
    };
    return AppPage(
      padding: EdgeInsets.zero,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Row(children: [
            RoundIconButton(Icons.arrow_back_rounded, onPressed: () => context.pop()),
            const SizedBox(width: 12),
            const AiOrb(size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Asisten Sysnergi', style: T.s(18, w: FontWeight.w600)),
                Row(children: [
                  Container(width: 7, height: 7, decoration: const BoxDecoration(color: AppColors.green, shape: BoxShape.circle)),
                  const SizedBox(width: 5),
                  Text('Paham data ${site?.name ?? ''}', style: T.small),
                ]),
              ]),
            ),
          ]),
        ),
        Expanded(
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            children: [
              for (final m in _msgs) ...[_bubble(m), const SizedBox(height: 14)],
              if (_thinking) Row(children: [const AiOrb(size: 28), const SizedBox(width: 8), Text('Sedang berpikir…', style: T.small)]),
              const SizedBox(height: 8),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.info_outline_rounded, size: 14, color: AppColors.muted),
                const SizedBox(width: 6),
                Text('Saran AI. Keputusan tetap di tangan Anda.', style: T.s(12, c: AppColors.muted)),
              ]),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(children: [
            SizedBox(
              height: 38,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                for (final c in chips) ...[
                  ActionChip(
                    label: Text(c, style: T.s(13, w: FontWeight.w500, c: AppColors.blue)),
                    backgroundColor: AppColors.glassStrong,
                    side: const BorderSide(color: AppColors.glassStroke),
                    shape: const StadiumBorder(),
                    onPressed: () => _send(c),
                  ),
                  const SizedBox(width: 8),
                ],
              ]),
            ),
            const SizedBox(height: 12),
            Container(
              height: 64,
              padding: const EdgeInsets.fromLTRB(18, 8, 8, 8),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(32), border: Border.all(color: AppColors.glassStroke, width: 1.5)),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    style: T.s(16),
                    textInputAction: TextInputAction.send,
                    onSubmitted: _send,
                    decoration: InputDecoration(border: InputBorder.none, hintText: 'Tanya atau ketik perintah…', hintStyle: T.s(16, c: AppColors.ink2)),
                  ),
                ),
                GestureDetector(
                  onTap: () => _send(_input.text),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppColors.blueGradient),
                    child: const Icon(Icons.arrow_upward_rounded, color: Colors.white),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _bubble(_Msg m) {
    if (m.fromUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: const BoxDecoration(
              gradient: AppColors.blueGradient,
              borderRadius: BorderRadius.only(topLeft: Radius.circular(22), topRight: Radius.circular(22), bottomLeft: Radius.circular(22), bottomRight: Radius.circular(6)),
            ),
            child: Text(m.text, style: T.s(15, c: Colors.white, h: 1.45)),
          ),
        ),
      );
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      const AiOrb(size: 28),
      const SizedBox(width: 8),
      Flexible(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.glassStrong,
            borderRadius: const BorderRadius.only(topLeft: Radius.circular(22), topRight: Radius.circular(22), bottomRight: Radius.circular(22), bottomLeft: Radius.circular(6)),
            border: Border.all(color: AppColors.glassStroke, width: 1.5),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(m.text, style: T.s(15, h: 1.45)),
            if (m.proposal != null) ...[const SizedBox(height: 12), _proposal(m.proposal!)],
          ]),
        ),
      ),
    ]);
  }

  Widget _proposal(_Proposal p) {
    final r = p.rule;
    Widget step(IconData i, String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            IconChip(i, size: 36),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(k, style: T.s(11, w: FontWeight.w600, c: AppColors.ink2, ls: 0.8)),
                Text(v, style: T.s(14, w: FontWeight.w600)),
              ]),
            ),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.line)),
        child: Column(children: [
          step(metricDef(p.parsed.metric).icon, 'JIKA', describeTrigger(r.trigger, p.hub)),
          const Divider(height: 1, color: AppColors.line),
          step(Icons.play_circle_outline_rounded, 'MAKA', describeAction(r.action, p.hub)),
          if (r.maxRunSec != null) ...[
            const Divider(height: 1, color: AppColors.line),
            step(Icons.verified_user_outlined, 'BATAS AMAN', 'Maksimal ${r.maxRunSec! ~/ 60} menit sekali jalan'),
          ],
        ]),
      ),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppColors.tint, borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          const Icon(Icons.history_rounded, size: 20, color: AppColors.blue),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              p.sim.triggers == 0
                  ? 'Uji ke data 7 hari: aturan ini tidak akan terpicu.'
                  : 'Uji ke data 7 hari: terpicu ${p.sim.triggers}×${r.action is RelayAction ? ', rata-rata ${p.sim.avgMinutes} menit' : ''}.',
              style: T.s(14, w: FontWeight.w500, h: 1.4),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 10),
      p.saved
          ? Row(children: [
              const Icon(Icons.check_circle_rounded, color: AppColors.green),
              const SizedBox(width: 8),
              Text('Sudah aktif', style: T.s(15, w: FontWeight.w600, c: AppColors.greenInk)),
            ])
          : PrimaryButton('Aktifkan', icon: Icons.check_rounded, height: 48, onPressed: () => _activate(p)),
    ]);
  }
}

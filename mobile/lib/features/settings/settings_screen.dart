import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/agenda_provider.dart';
import '../../providers/app_providers.dart';
import '../../providers/session_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _connectingGoogle = false;
  bool _connectingMicrosoft = false;

  Future<void> _editNickname(String current) async {
    final controller = TextEditingController(text: current);
    final updated = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nama Panggilan'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Contoh: Reza, Aulia, Raka...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (updated != null && updated.isNotEmpty) {
      await ref.read(sessionProvider.notifier).updateProfile(nickname: updated);
    }
  }

  Future<void> _editServerUrl() async {
    final cache = ref.read(localCacheProvider);
    final apiClient = ref.read(apiClientProvider);
    final controller = TextEditingController(
      text: cache.getCustomApiBaseUrl() ?? apiClient.effectiveBaseUrl,
    );
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Alamat Backend Server'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Gunakan IP LAN komputer (misal http://192.168.1.10:4000) bila menjalankan di HP Android fisik.',
              style: TextStyle(fontSize: 12.5),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                hintText: 'http://192.168.1.10:4000',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await cache.saveCustomApiBaseUrl(null);
              if (ctx.mounted) Navigator.pop(ctx, '');
            },
            child: const Text('Reset Default'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Simpan & Hubungkan'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (saved != null) {
      await cache.saveCustomApiBaseUrl(saved.isEmpty ? null : saved);
      await ref.read(sessionProvider.notifier).bootstrap();
      await ref.read(agendaProvider.notifier).loadAgenda();
    }
  }

  Future<void> _pickQuietTime({
    required bool isStart,
    required String currentHHmm,
  }) async {
    final parts = currentHHmm.split(':');
    final initial = TimeOfDay(
      hour: int.tryParse(parts.first) ?? (isStart ? 22 : 6),
      minute: int.tryParse(parts.last) ?? (isStart ? 0 : 30),
    );
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
    );
    if (picked == null) return;
    final formatted =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';

    await ref.read(sessionProvider.notifier).updateProfile(
          quietStart: isStart ? formatted : null,
          quietEnd: isStart ? null : formatted,
        );
  }

  Future<void> _handleOAuthConnect(String provider) async {
    setState(() {
      if (provider == 'google') {
        _connectingGoogle = true;
      } else {
        _connectingMicrosoft = true;
      }
    });

    final result =
        await ref.read(sessionProvider.notifier).connectCalendar(provider);

    if (mounted) {
      setState(() {
        if (provider == 'google') {
          _connectingGoogle = false;
        } else {
          _connectingMicrosoft = false;
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.success
                ? 'Berhasil terhubung ke ${provider == 'google' ? 'Google Calendar' : 'Microsoft Outlook'} (${result.email ?? 'Akun aktif'})'
                : result.errorMessage ?? 'Gagal menghubungkan akun kalender.',
          ),
        ),
      );
      if (result.success) {
        await ref.read(agendaProvider.notifier).loadAgenda(forceSync: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final profile = session.profile;
    final themeMode = ref.watch(themeModeProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pengaturan'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
        children: [
          // 1. Profil & Kepribadian Teman AI
          _SectionHeader(title: 'Teman AI & Profil'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: scheme.primary.withValues(alpha: 0.16),
                    child: Icon(Icons.person_rounded, color: scheme.primary),
                  ),
                  title: const Text('Nama Panggilan'),
                  subtitle: Text(profile.nickname),
                  trailing: const Icon(Icons.edit_rounded, size: 18),
                  onTap: () => _editNickname(profile.nickname),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Gaya Bicara Teman AI',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _PersonaChip(
                            label: '☕ Santai & Akrab',
                            selected: profile.aiPersona == 'santai',
                            onTap: () => ref
                                .read(sessionProvider.notifier)
                                .updateProfile(aiPersona: 'santai'),
                          ),
                          _PersonaChip(
                            label: '🌿 Tenang & Pendengar Baik',
                            selected: profile.aiPersona == 'tenang',
                            onTap: () => ref
                                .read(sessionProvider.notifier)
                                .updateProfile(aiPersona: 'tenang'),
                          ),
                          _PersonaChip(
                            label: '☀️ Ceria & Menyemangati',
                            selected: profile.aiPersona == 'ceria',
                            onTap: () => ref
                                .read(sessionProvider.notifier)
                                .updateProfile(aiPersona: 'ceria'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // 2. Koneksi Kalender Dua Arah
          _SectionHeader(title: 'Integrasi Kalender (Dua Arah)'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: Icon(Icons.auto_awesome_rounded, color: scheme.primary),
                  title: const Text('Mode Demo Kalender'),
                  subtitle: const Text(
                    'Tampilkan simulasi jadwal Outlook & Google agar langsung bisa dicoba.',
                  ),
                  value: profile.demoMode,
                  onChanged: (value) async {
                    await ref
                        .read(sessionProvider.notifier)
                        .updateProfile(demoMode: value);
                    await ref.read(agendaProvider.notifier).loadAgenda();
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0x1F2E8B57),
                    child: Icon(Icons.calendar_today_rounded,
                        color: AppTheme.googleGreen, size: 18),
                  ),
                  title: const Text('Google Calendar'),
                  subtitle: Text(
                    profile.connectedProviders.google.connected
                        ? 'Terhubung: ${profile.connectedProviders.google.email ?? 'Akun Google'}'
                        : session.capabilities.googleOAuth
                            ? 'Belum terhubung — ketuk untuk login OAuth 2.0'
                            : 'Siap dihubungkan (pasang GOOGLE_CLIENT_ID di backend/.env)',
                  ),
                  trailing: _connectingGoogle
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : profile.connectedProviders.google.connected
                          ? TextButton(
                              onPressed: () async {
                                await ref
                                    .read(sessionProvider.notifier)
                                    .disconnectCalendar('google');
                                await ref
                                    .read(agendaProvider.notifier)
                                    .loadAgenda();
                              },
                              child: const Text('Putuskan'),
                            )
                          : FilledButton.tonal(
                              onPressed: () => _handleOAuthConnect('google'),
                              child: const Text('Hubungkan'),
                            ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0x1F2B7CD3),
                    child: Icon(Icons.mail_outline_rounded,
                        color: AppTheme.outlookBlue, size: 18),
                  ),
                  title: const Text('Microsoft Outlook'),
                  subtitle: Text(
                    profile.connectedProviders.microsoft.connected
                        ? 'Terhubung: ${profile.connectedProviders.microsoft.email ?? 'Akun Microsoft'}'
                        : session.capabilities.microsoftOAuth
                            ? 'Belum terhubung — ketuk untuk login Microsoft Graph'
                            : 'Siap dihubungkan (pasang MICROSOFT_CLIENT_ID di backend/.env)',
                  ),
                  trailing: _connectingMicrosoft
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : profile.connectedProviders.microsoft.connected
                          ? TextButton(
                              onPressed: () async {
                                await ref
                                    .read(sessionProvider.notifier)
                                    .disconnectCalendar('microsoft');
                                await ref
                                    .read(agendaProvider.notifier)
                                    .loadAgenda();
                              },
                              child: const Text('Putuskan'),
                            )
                          : FilledButton.tonal(
                              onPressed: () => _handleOAuthConnect('microsoft'),
                              child: const Text('Hubungkan'),
                            ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // 3. Notifikasi & Jam Tenang
          _SectionHeader(title: 'Notifikasi & Jam Tenang'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: Icon(Icons.bedtime_rounded, color: scheme.primary),
                  title: const Text('Jam Tenang (Quiet Hours)'),
                  subtitle: Text(
                    profile.quietHoursEnabled
                        ? 'Notifikasi push dijeda ${profile.quietStart} – ${profile.quietEnd}'
                        : 'Nonaktif — semua notifikasi masuk langsung',
                  ),
                  value: profile.quietHoursEnabled,
                  onChanged: (v) => ref
                      .read(sessionProvider.notifier)
                      .updateProfile(quietHoursEnabled: v),
                ),
                if (profile.quietHoursEnabled) ...[
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _pickQuietTime(
                              isStart: true,
                              currentHHmm: profile.quietStart,
                            ),
                            icon: const Icon(Icons.nights_stay_outlined, size: 17),
                            label: Text('Mulai ${profile.quietStart}'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _pickQuietTime(
                              isStart: false,
                              currentHHmm: profile.quietEnd,
                            ),
                            icon: const Icon(Icons.wb_twilight_rounded, size: 17),
                            label: Text('Selesai ${profile.quietEnd}'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.notifications_active_rounded,
                      color: scheme.primary),
                  title: const Text('Tes Pengingat Lokal Sekarang'),
                  subtitle: const Text(
                    'Uji bunyi notifikasi + tombol Tandai Selesai & Tunda 10 Menit.',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    final msg = await ref
                        .read(sessionProvider.notifier)
                        .sendTestNotification();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text(msg)));
                    }
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // 4. Mode Suara & Tampilan
          _SectionHeader(title: 'Suara & Tampilan'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: Icon(Icons.record_voice_over_rounded,
                      color: scheme.primary),
                  title: const Text('Balasan Suara AI (Bahasa Indonesia)'),
                  subtitle: const Text(
                    'Bacakan balasan otomatis saat kamu mengobrol lewat mikrofon.',
                  ),
                  value: profile.voiceEnabled,
                  onChanged: (v) => ref
                      .read(sessionProvider.notifier)
                      .updateProfile(voiceEnabled: v),
                ),
                if (profile.voiceEnabled)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Row(
                      children: [
                        const Text('Kecepatan suara'),
                        Expanded(
                          child: Slider(
                            value: profile.ttsSpeechRate.clamp(0.3, 0.8),
                            min: 0.3,
                            max: 0.8,
                            divisions: 10,
                            onChanged: (v) => ref
                                .read(sessionProvider.notifier)
                                .updateProfile(ttsSpeechRate: v),
                          ),
                        ),
                      ],
                    ),
                  ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Tema Aplikasi',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<ThemeMode>(
                          segments: const [
                            ButtonSegment(
                              value: ThemeMode.system,
                              icon: Icon(Icons.brightness_auto_rounded),
                              label: Text('Sistem'),
                            ),
                            ButtonSegment(
                              value: ThemeMode.light,
                              icon: Icon(Icons.light_mode_rounded),
                              label: Text('Terang'),
                            ),
                            ButtonSegment(
                              value: ThemeMode.dark,
                              icon: Icon(Icons.dark_mode_rounded),
                              label: Text('Gelap'),
                            ),
                          ],
                          selected: {themeMode},
                          onSelectionChanged: (v) => ref
                              .read(themeModeProvider.notifier)
                              .setThemeMode(v.first),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          if (session.memories.isNotEmpty) ...[
            const SizedBox(height: 18),
            _SectionHeader(title: 'Memori yang Diingat TemanHari'),
            Card(
              child: Column(
                children: session.memories.map((mem) {
                  return ListTile(
                    dense: true,
                    leading: Icon(Icons.psychology_alt_rounded,
                        size: 20, color: scheme.primary),
                    title: Text(mem.content),
                    subtitle: Text(mem.category),
                    trailing: IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () => ref
                          .read(sessionProvider.notifier)
                          .deleteMemory(mem.id),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],

          const SizedBox(height: 18),
          _SectionHeader(title: 'Koneksi Server'),
          Card(
            child: ListTile(
              leading: Icon(
                session.isOnline
                    ? Icons.cloud_done_rounded
                    : Icons.cloud_off_rounded,
                color: session.isOnline ? AppTheme.googleGreen : scheme.error,
              ),
              title: Text(
                session.isOnline ? 'Terhubung ke Backend' : 'Mode Offline',
              ),
              subtitle: Text(ref.read(apiClientProvider).effectiveBaseUrl),
              trailing: const Icon(Icons.tune_rounded),
              onTap: _editServerUrl,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}

class _PersonaChip extends StatelessWidget {
  const _PersonaChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => onTap(),
    );
  }
}

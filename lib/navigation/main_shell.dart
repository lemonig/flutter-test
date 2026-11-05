import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../features/auth/data/repositories/auth_repository.dart';
import '../features/auth/presentation/version_update_dialog.dart';
import '../core/cache/app_cache_service.dart';
import '../features/auth/providers/auth_provider.dart';
import '../features/message/providers/message_providers.dart';
import '../shared/utils/toast.dart';

/// 底部导航外壳：Material 3 [NavigationBar] + 5 个目的地。
///
/// 每个 Tab 由 GoRouter 的独立分支承载，切换时保留各自滚动位置与页面栈。
/// 同时承担 M1-06 版本更新提示的弹出时机。
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const List<({String label, IconData icon})> tabs =
      <({String label, IconData icon})>[
        (label: '首页', icon: LucideIcons.house),
        (label: '消息', icon: LucideIcons.messageSquare),
        (label: '工作台', icon: LucideIcons.layoutGrid),
        (label: '信息填报', icon: LucideIcons.clipboardList),
        (label: '我的', icon: LucideIcons.circleUser),
      ];

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  String? _promptedVersion;

  /// 「我的」在 [MainShell.tabs] 里的位置。
  static const int _profileTabIndex = 4;

  void _onDestinationSelected(int index) {
    // 每次切回「我的」都重算缓存占用。
    //
    // FutureProvider 只算一次就缓存住，而用户很可能刚在签到 / 巡检里拍过照
    // （临时目录多出几 MB），不重算的话「清除缓存」会一直显示进页时的旧值，
    // 甚至明明有缓存却写着「暂无可清理的缓存」—— 实测踩到过。
    if (index == _profileTabIndex) {
      ref.invalidate(appCacheSizeProvider);
    }
    widget.navigationShell.goBranch(
      index,
      // 再次点击当前 Tab 时回到该分支初始页
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  Widget _tabIcon(IconData icon, {int badgeCount = 0}) {
    final Widget child = Icon(icon);
    if (badgeCount <= 0) return child;
    return Badge.count(count: badgeCount, maxCount: 99, child: child);
  }

  @override
  Widget build(BuildContext context) {
    final int unread = ref.watch(unreadMessageCountProvider);

    ref.listen<AsyncValue<AppVersionInfo?>>(appVersionProvider, (
      AsyncValue<AppVersionInfo?>? previous,
      AsyncValue<AppVersionInfo?> next,
    ) {
      final AppVersionInfo? info = next.value;
      if (info == null || _promptedVersion == info.version) return;
      _promptedVersion = info.version;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!context.mounted) return;
        final bool goUpdate = await showVersionUpdateDialog(context, info);
        if (goUpdate && context.mounted) {
          showToast(context, '请前往应用市场更新到 v${info.version}');
        }
      });
    });

    return Scaffold(
      body: widget.navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: widget.navigationShell.currentIndex,
        onDestinationSelected: _onDestinationSelected,
        destinations: <Widget>[
          for (int i = 0; i < MainShell.tabs.length; i++)
            NavigationDestination(
              icon: _tabIcon(
                MainShell.tabs[i].icon,
                badgeCount: i == 1 ? unread : 0,
              ),
              selectedIcon: _tabIcon(
                MainShell.tabs[i].icon,
                badgeCount: i == 1 ? unread : 0,
              ),
              label: MainShell.tabs[i].label,
            ),
        ],
      ),
    );
  }
}

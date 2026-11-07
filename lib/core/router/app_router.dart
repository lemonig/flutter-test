import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/amap/map_picker_page.dart';
import '../../features/auth/presentation/change_password_page.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/auth/presentation/splash_page.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/discussion/presentation/discussion_page.dart';
import '../../features/discussion/presentation/post_pin_page.dart';
import '../../features/home/data/models/task_item.dart';
import '../../features/home/presentation/create_attend_page.dart';
import '../../features/home/presentation/create_task_page.dart';
import '../../features/home/presentation/home_page.dart';
import '../../features/home/presentation/address_list_page.dart';
import '../../features/home/presentation/search_page.dart';
import '../../features/home/presentation/submit_inspection_page.dart';
import '../../features/home/presentation/task_detail_page.dart';
import '../../features/message/data/models/message_models.dart';
import '../../features/message/presentation/message_list_page.dart';
import '../../features/message/presentation/message_page.dart';
import '../../features/profile/presentation/about_page.dart';
import '../../features/profile/presentation/help_feedback_page.dart';
import '../../features/profile/presentation/my_events_page.dart';
import '../../features/profile/presentation/privacy_policy_page.dart';
import '../../features/profile/presentation/profile_detail_page.dart';
import '../../features/profile/presentation/profile_page.dart';
import '../../features/workbench/data/models/workbench_models.dart';
import '../../features/workbench/presentation/apply_pages.dart';
import '../../features/workbench/presentation/apply_record_pages.dart';
import '../../features/workbench/presentation/directory_pages.dart';
import '../../features/workbench/presentation/report_pages.dart';
import '../../features/workbench/presentation/stats_pages.dart';
import '../../features/workbench/presentation/workbench_page.dart';
import '../../features/workbench/providers/workbench_providers.dart';
import '../../navigation/main_shell.dart';
import '../../shared/widgets/empty_state.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'root',
);

/// 路由表（M0-09）：
/// - StatefulShellRoute 承载 5 个 Tab，分支独立 Navigator 栈、切换保活
/// - 全屏路由（详情 / 改密）与 Shell 平级，覆盖底栏
/// - redirect 统一鉴权，未登录跳登录页并记录原地址，登录后回跳
final Provider<GoRouter> routerProvider = Provider<GoRouter>((Ref ref) {
  final ChangeNotifier refresh = _AuthRefreshNotifier(ref);
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/splash',
    refreshListenable: refresh,
    debugLogDiagnostics: kDebugMode,
    redirect: (BuildContext context, GoRouterState state) =>
        _authGuard(ref, state),
    routes: <RouteBase>[
      GoRoute(
        path: '/splash',
        name: 'splash',
        builder: (BuildContext context, GoRouterState state) =>
            const SplashPage(),
      ),
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (BuildContext context, GoRouterState state) =>
            const LoginPage(),
      ),
      GoRoute(
        path: '/change-password',
        name: 'changePassword',
        builder: (BuildContext context, GoRouterState state) =>
            const ChangePasswordPage(),
      ),
      GoRoute(
        path: '/my-events',
        name: 'myEvents',
        builder: (BuildContext context, GoRouterState state) =>
            const MyEventsPage(),
      ),
      // 消息明细：路径用单数 `/message/:code`，和底栏的 `/messages` 分开，
      // 避免 `/messages/2` 这种「Tab 路径 + 参数」的歧义。
      GoRoute(
        path: '/message/:code',
        name: 'messageList',
        builder: (BuildContext context, GoRouterState state) {
          final MessageType? type = MessageType.fromCode(state.pathParameters['code']);
          if (type == null) {
            return const Scaffold(
              body: SafeArea(
                child: EmptyState(
                  icon: LucideIcons.circleHelp,
                  title: '未知的消息分类',
                  message: '该分类可能已下线，返回消息列表后重试',
                ),
              ),
            );
          }
          return MessageListPage(type: type);
        },
      ),
      // 刻意不用 `/profile/edit`：`/profile` 是 Shell 分支下的路径，
      // 名字太容易和底栏 Tab 混在一起，改成独立命名。
      GoRoute(
        path: '/profile-info',
        name: 'profileInfo',
        builder: (BuildContext context, GoRouterState state) =>
            const ProfileDetailPage(),
      ),
      GoRoute(
        path: '/about',
        name: 'about',
        builder: (BuildContext context, GoRouterState state) =>
            const AboutPage(),
      ),
      GoRoute(
        path: '/privacy-policy',
        name: 'privacyPolicy',
        builder: (BuildContext context, GoRouterState state) =>
            const PrivacyPolicyPage(),
      ),
      GoRoute(
        path: '/help-feedback',
        name: 'helpFeedback',
        builder: (BuildContext context, GoRouterState state) =>
            const HelpFeedbackPage(),
      ),
      // 地图选点（M0-07）：坐标走 query 参数（便于深链），结果用 pop 返回。
      GoRoute(
        path: '/map-picker',
        name: 'mapPicker',
        builder: (BuildContext context, GoRouterState state) => MapPickerPage(
          initialLatitude: double.tryParse(
            state.uri.queryParameters['lat'] ?? '',
          ),
          initialLongitude: double.tryParse(
            state.uri.queryParameters['lng'] ?? '',
          ),
        ),
      ),
      // ── 工作台（M7-02 ~ M7-10）──────────────────────────────
      // 静态段必须排在动态段之前，否则被 :kind / :id 吃掉。
      GoRoute(
        path: '/workbench/stats/:kind',
        name: 'workbenchStats',
        builder: (BuildContext context, GoRouterState state) => StatisticsPage(
          kind: StatsKind.values.firstWhere(
            (StatsKind k) => k.name == state.pathParameters['kind'],
            orElse: () => StatsKind.abnormal,
          ),
        ),
      ),
      GoRoute(
        path: '/workbench/directory/:kind',
        name: 'workbenchDirectory',
        builder: (BuildContext context, GoRouterState state) => DirectoryPage(
          kind: DirectoryKind.values.firstWhere(
            (DirectoryKind k) => k.name == state.pathParameters['kind'],
            orElse: () => DirectoryKind.station,
          ),
        ),
      ),
      GoRoute(
        path: '/addresses',
        name: 'addresses',
        builder: (BuildContext context, GoRouterState state) =>
            const AddressListPage(),
      ),
      GoRoute(
        path: '/discussion/new',
        name: 'discussionNew',
        builder: (BuildContext context, GoRouterState state) =>
            const PostPinPage(),
      ),
      GoRoute(
        path: '/search',
        name: 'search',
        builder: (BuildContext context, GoRouterState state) =>
            const SearchPage(),
      ),
      GoRoute(
        path: '/workbench/apply-records',
        name: 'workbenchApplyRecords',
        builder: (BuildContext context, GoRouterState state) =>
            const ApplyRecordsPage(),
      ),
      GoRoute(
        path: '/workbench/approvals',
        name: 'workbenchApprovals',
        builder: (BuildContext context, GoRouterState state) =>
            const ApprovalCenterPage(),
      ),
      GoRoute(
        path: '/workbench/report/:kind/new',
        name: 'workbenchReportNew',
        builder: (BuildContext context, GoRouterState state) => ReportFormPage(
          kind: _reportKind(state.pathParameters['kind']),
        ),
      ),
      GoRoute(
        path: '/workbench/report/:kind/:id',
        name: 'workbenchReportDetail',
        builder: (BuildContext context, GoRouterState state) =>
            ReportDetailPage(
              kind: _reportKind(state.pathParameters['kind']),
              id: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
            ),
      ),
      GoRoute(
        path: '/workbench/report/:kind',
        name: 'workbenchReportList',
        builder: (BuildContext context, GoRouterState state) => ReportListPage(
          kind: _reportKind(state.pathParameters['kind']),
        ),
      ),
      GoRoute(
        path: '/workbench/apply/:kind/submit',
        name: 'workbenchApplySubmit',
        builder: (BuildContext context, GoRouterState state) => ApplySubmitPage(
          kind: _applyType(state.pathParameters['kind']),
        ),
      ),
      GoRoute(
        path: '/workbench/apply/:kind',
        name: 'workbenchApplyPick',
        builder: (BuildContext context, GoRouterState state) => ShopPickPage(
          kind: _applyType(state.pathParameters['kind']),
        ),
      ),
      GoRoute(
        path: '/task/create',
        name: 'taskCreate',
        builder: (BuildContext context, GoRouterState state) =>
            const CreateTaskPage(),
      ),
      GoRoute(
        path: '/task/:id',
        name: 'taskDetail',
        builder: (BuildContext context, GoRouterState state) => TaskDetailPage(
          category: TaskCategory.abnormal,
          id: state.pathParameters['id'] ?? '',
          item: state.extra is TaskItem ? state.extra! as TaskItem : null,
        ),
      ),
      GoRoute(
        path: '/inspection/:id/submit',
        name: 'inspectionSubmit',
        builder: (BuildContext context, GoRouterState state) =>
            SubmitInspectionPage(recordId: state.pathParameters['id'] ?? ''),
      ),
      GoRoute(
        path: '/inspection/:id',
        name: 'inspectionDetail',
        builder: (BuildContext context, GoRouterState state) => TaskDetailPage(
          category: TaskCategory.inspection,
          id: state.pathParameters['id'] ?? '',
          item: state.extra is TaskItem ? state.extra! as TaskItem : null,
        ),
      ),
      // 必须排在 `/attend/:id` 之前：GoRouter 按注册顺序匹配，
      // 否则 `/attend/create` 会被动态段吃掉（`/task/create` 踩过一次）。
      GoRoute(
        path: '/attend/create',
        name: 'attendCreate',
        builder: (BuildContext context, GoRouterState state) =>
            const CreateAttendPage(),
      ),
      GoRoute(
        path: '/attend/:id',
        name: 'attendDetail',
        builder: (BuildContext context, GoRouterState state) => TaskDetailPage(
          category: TaskCategory.signIn,
          id: state.pathParameters['id'] ?? '',
          item: state.extra is TaskItem ? state.extra! as TaskItem : null,
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder:
            (
              BuildContext context,
              GoRouterState state,
              StatefulNavigationShell navigationShell,
            ) {
              return MainShell(navigationShell: navigationShell);
            },
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/home',
                name: 'home',
                builder: (BuildContext context, GoRouterState state) =>
                    const HomePage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/messages',
                name: 'messages',
                builder: (BuildContext context, GoRouterState state) =>
                    const MessagePage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/workbench',
                name: 'workbench',
                builder: (BuildContext context, GoRouterState state) =>
                    const WorkbenchPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/discussion',
                name: 'discussion',
                builder: (BuildContext context, GoRouterState state) =>
                    const DiscussionPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/profile',
                name: 'profile',
                builder: (BuildContext context, GoRouterState state) =>
                    const ProfilePage(),
              ),
            ],
          ),
        ],
      ),
    ],
    errorBuilder: (BuildContext context, GoRouterState state) => Scaffold(
      appBar: AppBar(title: const Text('页面不存在')),
      body: EmptyState(
        icon: LucideIcons.compass,
        title: '没有找到这个页面',
        message: state.uri.toString(),
        actionLabel: '返回首页',
        onAction: () => GoRouter.of(context).go('/home'),
      ),
    ),
  );
});

/// 鉴权重定向逻辑，可单独测试。
String? authGuardFor({
  required AsyncValue<AuthState> auth,
  required String matchedLocation,
  required Uri uri,
}) {
  final AuthState? value = auth.value;
  final bool initializing = auth.isLoading || value == null;
  final bool loggedIn = value?.isAuthenticated ?? false;
  final bool onSplash = matchedLocation == '/splash';
  final bool onLogin = matchedLocation == '/login';

  /// 恢复用户原本想去的地址。
  /// 冷启动 / 深链直达时，鉴权尚未完成会先经过 /splash，
  /// 必须把目标带在 from 参数里，否则登录态恢复后会被统一送回首页。
  String originalTarget() {
    final String? pending = uri.queryParameters['from'];
    if (pending != null &&
        pending.isNotEmpty &&
        pending != '/splash' &&
        !pending.startsWith('/login')) {
      return pending;
    }
    final String current = uri.toString();
    if (onSplash || onLogin || current.isEmpty || current == '/') {
      return '/home';
    }
    return current;
  }

  if (initializing) {
    if (onSplash) return null;
    return '/splash?from=${Uri.encodeComponent(originalTarget())}';
  }

  if (!loggedIn) {
    if (onLogin) return null;
    final String target = originalTarget();
    // 没有明确深链目标时保持简洁的登录 URL。
    if (onSplash && uri.queryParameters['from'] == null) return '/login';
    return '/login?from=${Uri.encodeComponent(target)}';
  }

  if (onSplash || onLogin) return originalTarget();
  return null;
}

String? _authGuard(Ref ref, GoRouterState state) => authGuardFor(
  auth: ref.read(authProvider),
  matchedLocation: state.matchedLocation,
  uri: state.uri,
);

/// 鉴权状态变化时通知 GoRouter 重新计算 redirect。
/// 不重建 router，因此 Tab 栈与滚动位置不会丢失。
class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier(Ref ref) {
    ref.listen<AsyncValue<AuthState>>(authProvider, (
      AsyncValue<AuthState>? previous,
      AsyncValue<AuthState> next,
    ) {
      notifyListeners();
    });
  }
}

/// 供页面调用的详情页路径。
String detailPathFor(TaskCategory category, String id) => switch (category) {
  TaskCategory.abnormal => '/task/$id',
  TaskCategory.inspection => '/inspection/$id',
  TaskCategory.signIn => '/attend/$id',
};

/// 路径参数里的工作台枚举解析；未知值兜底到第一个成员，
/// 让错误链接落到列表页而不是白屏。
ReportKind _reportKind(String? raw) {
  for (final ReportKind kind in ReportKind.values) {
    if (kind.name == raw) return kind;
  }
  return ReportKind.mileage;
}

ApplyType _applyType(String? raw) {
  for (final ApplyType type in ApplyType.values) {
    if (type.name == raw) return type;
  }
  return ApplyType.reagent;
}

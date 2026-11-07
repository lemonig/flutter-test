import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/network/api_response.dart';
import '../../../shared/utils/backend_time.dart';
import '../../../shared/widgets/app_avatar.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/photo_viewer_page.dart';
import '../data/models/pin_post.dart';
import '../providers/pin_providers.dart';
import 'pin_detail_page.dart';

/// 信息填报（M8 讨论区）：频道分段 + 帖子流 + 发帖入口。
///
/// 对照 iOS 原生讨论区（`pin/list` / `pin/channel`）：
/// 频道「全部」+ `pin/channel` 返回的频道做分段，各频道独立分页缓存；
/// 帖子卡点击进详情（评论/点赞在详情页）。原静态「填报进度」卡已移除
/// —— 那是外部 H5 填报系统的概念，原生接口没有对应物。
class DiscussionPage extends ConsumerStatefulWidget {
  const DiscussionPage({super.key});

  @override
  ConsumerState<DiscussionPage> createState() => _DiscussionPageState();
}

class _DiscussionPageState extends ConsumerState<DiscussionPage>
    with TickerProviderStateMixin {
  TabController? _tabController;

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  void _ensureTabs(int length) {
    if (_tabController?.length == length) return;
    _tabController?.dispose();
    _tabController = length > 0
        ? TabController(length: length, vsync: this)
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<List<PinChannel>> channels = ref.watch(pinChannelsProvider);
    final List<PinChannel> list = channels.asData?.value ?? const <PinChannel>[];
    _ensureTabs(list.length + 1);

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('信息填报'),
        actions: <Widget>[
          IconButton(
            tooltip: '发帖',
            onPressed: () async {
              await context.push('/discussion/new');
              ref.invalidate(pinListProvider(_currentChannelId));
            },
            icon: const Icon(LucideIcons.penLine, size: 20),
          ),
          const SizedBox(width: 8),
        ],
        bottom: list.isEmpty
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(46),
                child: AppBar(
                  automaticallyImplyLeading: false,
                  backgroundColor: Colors.transparent,
                  surfaceTintColor: Colors.transparent,
                  title: TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    dividerColor: Colors.transparent,
                    labelColor: theme.colorScheme.primary,
                    unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
                    indicatorColor: theme.colorScheme.primary,
                    tabs: <Widget>[
                      const Tab(text: '全部'),
                      for (final PinChannel channel in list)
                        Tab(text: channel.name),
                    ],
                  ),
                ),
              ),
      ),
      body: list.isEmpty
          // 频道未就绪（loading / 失败）：列表仍按「全部」渲染，
          // 频道条失败时静默降级为全部流，不阻塞主内容。
          ? const _PostListView(channelId: 0)
          : TabBarView(
              controller: _tabController,
              children: <Widget>[
                const _PostListView(channelId: 0),
                for (final PinChannel channel in list)
                  _PostListView(channelId: channel.id),
              ],
            ),
    );
  }

  int get _currentChannelId {
    final int index = _tabController?.index ?? 0;
    if (index <= 0) return 0;
    final List<PinChannel> list =
        ref.read(pinChannelsProvider).asData?.value ?? const <PinChannel>[];
    if (index - 1 >= list.length) return 0;
    return list[index - 1].id;
  }
}

/// 单个频道的帖子流：下拉刷新 + 触底加载 + 空态。
class _PostListView extends ConsumerStatefulWidget {
  const _PostListView({required this.channelId});

  final int channelId;

  @override
  ConsumerState<_PostListView> createState() => _PostListViewState();
}

class _PostListViewState extends ConsumerState<_PostListView> {
  @override
  Widget build(BuildContext context) {
    final AsyncValue<PinListState> page = ref.watch(
      pinListProvider(widget.channelId),
    );

    return page.when(
      loading: () => const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      error: (Object error, StackTrace stack) => EmptyState(
        icon: LucideIcons.triangleAlert,
        title: '帖子加载失败',
        message: error is AppException ? error.userMessage : '请稍后重试',
        actionLabel: '重试',
        onAction: () => ref.invalidate(pinListProvider(widget.channelId)),
      ),
      data: (PinListState state) {
        if (state.items.isEmpty) {
          return const EmptyState(
            icon: LucideIcons.messagesSquare,
            title: '还没有帖子',
            message: '点右上角「发帖」分享第一条反馈或经验',
          );
        }
        return NotificationListener<ScrollNotification>(
          onNotification: (ScrollNotification notification) {
            if (notification.metrics.pixels >
                notification.metrics.maxScrollExtent - 200) {
              ref.read(pinListProvider(widget.channelId).notifier).loadMore();
            }
            return false;
          },
          child: RefreshIndicator(
            onRefresh: () =>
                ref.read(pinListProvider(widget.channelId).notifier).refresh(),
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: state.items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (BuildContext context, int index) => PinPostCard(
                post: state.items[index],
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (BuildContext context) => PinDetailPage(
                      pinId: state.items[index].id,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 帖子卡：作者行 + 正文 + 缩略图 + 频道标签 + 互动数。
class PinPostCard extends StatelessWidget {
  const PinPostCard({super.key, required this.post, required this.onTap});

  final PinPost post;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  AppAvatar(label: post.nickname, size: 34, radius: 11),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          post.nickname.isEmpty ? '匿名' : post.nickname,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          formatBackendFriendly(post.gmtCreate, empty: ''),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (post.channel.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        post.channel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                ],
              ),
              if (post.title.isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                Text(
                  post.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (post.content.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  post.content,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                ),
              ],
              if (post.pictures.isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                _PictureGrid(
                  urls: post.pictures.take(3).toList(growable: false),
                  moreCount: post.pictures.length > 3
                      ? post.pictures.length - 3
                      : 0,
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Icon(
                    LucideIcons.messageCircle,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${post.commentCount}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Icon(
                    LucideIcons.thumbsUp,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${post.likeCount}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
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
}

/// 列表卡里的缩略图（最多 3 张 + 「+N」角标）；预览在详情页。
class _PictureGrid extends StatelessWidget {
  const _PictureGrid({required this.urls, required this.moreCount});

  final List<String> urls;
  final int moreCount;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 88,
      child: Row(
        children: <Widget>[
          for (final String url in urls)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      Image.network(
                        url,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => ColoredBox(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHigh,
                          child: const Icon(LucideIcons.imageOff, size: 18),
                        ),
                      ),
                      if (moreCount > 0 && url == urls.last)
                        ColoredBox(
                          color: Colors.black38,
                          child: Center(
                            child: Text(
                              '+$moreCount',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(color: Colors.white),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 图片九宫格（详情页用），点击全屏预览。
class PinPhotoGrid extends StatelessWidget {
  const PinPhotoGrid({super.key, required this.urls});

  final List<String> urls;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (int i = 0; i < urls.length; i++)
          GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (BuildContext context) =>
                    PhotoViewerPage(images: urls, initialIndex: i),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                urls[i],
                width: 96,
                height: 96,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  width: 96,
                  height: 96,
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  child: const Icon(LucideIcons.imageOff, size: 20),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

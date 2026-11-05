import '../../../../core/constants/app_colors.dart';

/// 信息填报（讨论区）帖子。
class PostItem {
  const PostItem({
    required this.id,
    required this.author,
    required this.department,
    required this.timeText,
    required this.title,
    required this.body,
    required this.tag,
    this.likeCount = 0,
    this.commentCount = 0,
  });

  final String id;
  final String author;
  final String department;
  final String timeText;
  final String title;
  final String body;
  final String tag;
  final int likeCount;
  final int commentCount;

  Tone get tone => switch (tag) {
    '异常上报' => Tone.danger,
    '巡检记录' => Tone.brand,
    '经验分享' => Tone.success,
    _ => Tone.neutral,
  };
}

/// 本地演示数据。
const List<PostItem> mockPostItems = <PostItem>[
  PostItem(
    id: 'post-01',
    author: '张伟',
    department: '南湖片区 · 运维一组',
    timeText: '10 分钟前',
    title: '南湖站采水单元压力异常处置记录',
    body: '到场后先关闭进水阀，拆检蠕动泵发现泵管老化开裂，更换备用泵管并复测流量，压力恢复至 0.18MPa，已连续观察 30 分钟无波动。',
    tag: '异常上报',
    likeCount: 12,
    commentCount: 3,
  ),
  PostItem(
    id: 'post-02',
    author: '李娜',
    department: '运河片区 · 运维二组',
    timeText: '1 小时前',
    title: '三塔断面 COD 标液核查结果',
    body: '标液核查偏差 +2.6%，在允许范围内。已同步更新试剂有效期台账，下周计划做一次完整的零点漂移检查。',
    tag: '巡检记录',
    likeCount: 8,
    commentCount: 1,
  ),
  PostItem(
    id: 'post-03',
    author: '王强',
    department: '秀洲片区 · 运维三组',
    timeText: '昨天 17:20',
    title: '夏季站房空调巡检的几点经验',
    body: '机柜温度超过 35℃ 时数据采集器容易重启。建议把空调滤网清理纳入月度巡检清单，同时在机柜顶部加装温度贴片，便于现场快速判断。',
    tag: '经验分享',
    likeCount: 21,
    commentCount: 6,
  ),
  PostItem(
    id: 'post-04',
    author: '陈晨',
    department: '海盐片区 · 运维四组',
    timeText: '11-02 09:05',
    title: '澉浦断面 4G 模块掉线复盘',
    body: '掉线原因为信号强度长期低于 -105dBm，已更换高增益天线并调整安装角度。建议同类断面统一排查天线老化情况。',
    tag: '异常上报',
    likeCount: 6,
    commentCount: 2,
  ),
];

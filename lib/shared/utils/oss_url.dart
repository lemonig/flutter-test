/// OSS 图片地址补全。
///
/// 后端存在两种返回形态，客户端必须都吃得下：
/// - `PictureBO { picture: 'ops/xxx.jpg', url: 'https://...' }` —— 直接用 `url`；
/// - 裸 `List<String>`（巡检备注图、巡检项 `pictures`）—— 只有 objectKey，
///   需要自己拼 OSS 域名，否则 `Image.network` 拿到相对路径直接报错。
///
/// 域名与后端 `AliyunOss.pictureUrl` 保持一致，别改这里改成别的区域。
const String kOssBaseUrl = 'https://grean-ops.oss-cn-hangzhou.aliyuncs.com/';

String resolveOssUrl(String raw) {
  final String value = raw.trim();
  if (value.isEmpty) return '';
  if (value.startsWith('http://') || value.startsWith('https://')) return value;
  return kOssBaseUrl + (value.startsWith('/') ? value.substring(1) : value);
}

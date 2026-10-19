# Clipo 原生交付记录

2026-10-19。新建 Swift / SwiftUI iPhone 应用，最低 iOS 17。播放器与编辑引擎使用 AVFoundation；系统照片/文件选择和 Apple 购买使用真实平台界面。没有 Flutter、Web UI 或示例人物媒体。

## 已确认范围

- 应用名称 Clipo，临时 Bundle ID `com.clipo.video`，API `https://devapi.io-d.cc`。
- Figma 是功能参考而非逐像素复制。已通过用户 Chrome 观察首页、视频工具箱、频道/文件夹、播放与额度弹层；参考总览保存在 `ProjectMaterials/DesignReferences/figma-overview.png`。
- 首页输入外部链接/短码，支持访问密码、最近打开记录、推荐频道和来源入口。
- 推荐/搜索 Feed，原生纵向分页，当前页播放、离页释放、后台暂停、循环、静音、倍速、进度、保存与分享。
- 频道和文件夹分页、真实空/失败/重试状态；链接只通过文档给出的服务解析，不声称任意网站都能抓取。
- 本机视频导入、剪辑、中心画幅裁切、90°旋转、镜像、0.5–2×变速、静音、分辨率压缩、MP4 导出、M4A 音轨提取。变更可预览，原始文件保留。
- 收藏、历史、导入与导出按本机存储；不是服务器云同步，不伪造用户头像、关注、粉丝、评论或远端互动。
- 一键登录使用文档的后端游客接口；离线编辑入口仅开放本机工作台，不伪造登录。
- 月度/年度订阅、恢复与持久验单；Google 激励广告和额度。

## UI 方向与资产

首页是操作入口，播放页是沉浸浏览，编辑页是单视频工作台。深墨色底、荧光黄主操作、系统原生可缩放文字与项目原创位图图标组成统一视觉系统。无文字 Tabbar 保留辅助功能名称和选中状态。

实际读取并使用 `jpg`、`ui-design-reference`、`ui-taste`、`claude-design`、`gpt-image-2`、`imagegen`。已评估 Taste 前端与 Garden 网页模块；本项目不采用其网页实现流程。

- 原创 App Icon 与 16 个导航/操作图标由 Host-Native 内置图像工具生成。
- 原始文件、生成提示词位于 `ProjectMaterials/UIAssets`。图标 atlas 使用原图分格显示与 screen 混合，不使用代码绘图、SF Symbols 或库存图标。
- App Icon 的发行副本规范为 1024×1024；保留生成原图。
- `ProjectMaterials`、文档、提示词、工程配置不在 Copy Bundle Resources 内。只显式加入 Asset Catalog、Commerce.json 和 PrivacyInfo.xcprivacy。
- 未内置头像、人物照片、视频。内容由实际接口或用户自行导入。

## 订阅与额度配置

`Config/Clipo.xcconfig`：域名、Bundle ID、签名团队、AdMob App ID、协议链接。
`Clipo/Resources/Commerce.json`：商品 ID、订单 usdPrice、广告类型和额度策略。

| 方案 | 商品 ID | 后端 usdPrice | 建议 App Store 参考 USD 价格 |
|---|---|---|---|
| Monthly | com.clipo.video.premium.monthly | 999 | 9.99 |
| Yearly | com.clipo.video.premium.yearly | 9999 | 99.99 |

商品类型：自动续期订阅，建议同一订阅组。以上是待在 App Store Connect 创建的配置建议；页面只展示 StoreKit 返回的实际本地化价格，没有硬编码成交价或虚构优惠。

用户授权先拟定的广告策略：adType=2；每日5次观看，前三次完整广告各加3次，第4次广告后当日无限观看；每日基础收藏5次，每个完整广告加5次。每天本机时区凌晨5点重置。后端明确的 dailyWatchLimit / favoriteBaseLimit / 三阶段奖励字段可覆盖基础值；文档内冲突的 unlimitedAfterAdCount 不擅自套用，阈值在 Commerce.json 管理。

已观看的视频同日重播不重复扣次。额度记录使用用户 ID 分隔并持久化到 Keychain；新收藏扣次、取消收藏不返还已使用次数。额度属于客户端计数，文档没有服务端核销接口，不声称可防设备改时或跨设备滥用。没有广告填充时显示失败/重试，不伪装广告观看或发放所谓幸运奖励。

## 接口与交易约束

- 业务成功须 HTTP 2xx 且整数 code=0；请求超时15秒。
- 发布配置、游客登录、批量频道信息不加 Authorization；其余业务加 Bearer Token。
- 普通已认证请求401后执行游客登录并重试一次；并发重登复用进行中的任务。
- token、安装UUID、交易归属在 Keychain；不写日志或 UserDefaults。uniqueId 按文档允许为空，不额外访问公网 IP 服务。
- 每个订单保存后端订单号、原用户、凭据、API host、商品、验单配置和交易 ID。恢复不根据商品或当前页面推测归属。
- buySuccess 成功之后必须持久记录并读回确认，再 finishTransaction。未确认的交易保留，前台恢复与手动重试均可续验。
- 401 的支付确认不迁移到其他游客。原用户凭据失效时保留待验；新凭据仅在 userId 与原归属相同的情况下使用。
- 未匹配原订单的跨安装恢复需后端提供订单归属恢复接口；当前10个接口不含此能力，交易保留待核对，不伪称恢复成功。
- 会员权益以 member/user/get 的到期时间为准，不以购买按钮或本地 flag 直接解锁。

## 仍需配置或确认

1. 在 Apple/后端注册最终 Bundle ID；当前按用户要求先使用 com.clipo.video。设置开发团队与签名。
2. 在 App Store Connect 创建上述商品并在后端登记价格映射；确认完整交易幂等行为与跨安装恢复接口。
3. 提供 AdMob iOS App ID，写入 xcconfig，后端对应 appId 必须匹配。奖励广告单元从发布配置读取。SDK 已通过官方 SPM 依赖声明，尚未下载/解析。其他广告平台的中介适配器需按实际平台另外配置。
4. 设置可访问的隐私政策和服务条款 URL；未设置时购买流程会明确暂停。账号删除/支持接口未在文档中提供，未虚构账号删除功能。
5. 广告隐私通过 UMP 处理并提供必要的隐私选项入口。上架前结合最终广告中介、后端收集情况确认隐私清单与 App Store 隐私披露，补齐需要的 SKAdNetwork IDs。

## 已做与未做的验证

已做源码/配置/资源静态检查（接口原文保留既有尾随空格）：plist 和 pbxproj 可解析，Swift 文件与资源显式 target 归属、资源文件存在、原始资料排除、主域名与ID一致、素材尺寸、JSON 结构、差异与空白检查、交易结束顺序人工检查。当前15个Swift源文件、3项显式资源引用，运行时源资源合计约2.59 MiB；这不是IPA或安装体积。

未做编译、类型检查、自动测试、Xcode/模拟器/设备运行、真实界面渲染、业务接口请求、StoreKit 沙盒购买/恢复、广告播放、视频解码/导出实测。源码完成不等于上述运行结果已通过。

## 参考

- Figma：https://www.figma.com/design/LbCyJ0BI2CUGKzjw5fBTgD/LT-%E5%AF%B9%E6%8E%A5-UI?node-id=198-2270
- 接口原文：本目录 API-reference.md（保留用户提供内容，不将文档示例当成本次配置）。
- Apple AVFoundation 编辑：https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/AVFoundationPG/Articles/03_Editing.html
- Google 官方激励广告：https://developers.google.com/admob/ios/rewarded
- Google 官方 UMP：https://developers.google.com/admob/ios/privacy
- Google 官方 SPM：https://github.com/googleads/swift-package-manager-google-mobile-ads

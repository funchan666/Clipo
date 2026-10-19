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
| Monthly | ypsmwxmscbzeixig | 999 | 9.99 |
| Yearly | xfpkaphmqxhtgzvx | 9999 | 99.99 |

商品 ID 按用户要求使用 16 位纯小写字母；App Store Connect 登记时必须逐字一致。StoreKit 查询和创建订单的 rightsName 共用 Commerce.json 中的 ID，既有交易账本保留原商品 ID，不改写历史订单。

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
3. 当前已启用 Google 官方 iOS 测试广告（详见下节）。上线前将 CLIPO_ADS_TEST_MODE 改为 NO，并将 CLIPO_GOOGLE_ADS_APP_ID 替换为正式 App ID；正式模式从后台读取 adType=2、advertiser=google 的广告单元，appId 必须与本机一致。官方 SPM 依赖已解析，并参与本次 iOS 编译。其他广告平台的中介适配器需按实际平台另外配置。
4. 设置可访问的隐私政策和服务条款 URL；未设置时购买流程会明确暂停。账号删除/支持接口未在文档中提供，未虚构账号删除功能。
5. 广告隐私通过 UMP 处理并提供必要的隐私选项入口。上架前结合最终广告中介、后端收集情况确认隐私清单与 App Store 隐私披露，补齐需要的 SKAdNetwork IDs。

## 启动界面（2026-10-19 增量）

- `Clipo/Resources/LaunchScreen.storyboard`：安全区中央 108pt 图标，下方留 27pt 后显示静态细短 loading；背景为现有 LaunchBackground 深墨绿（sRGB 0.055 / 0.065 / 0.060）。系统 Launch 不执行动画代码，也不发网络请求。
- `ClipoStartupHost` / `ClipoStartupView`：同一组图像、位置和背景，loading 以透明度轻柔呼吸。普通启动展示 750ms 后淡入原界面，减少动态效果时缩短为 150ms、取消动画。这是本地品牌过渡，不是网络进度或验单进度。
- 用户已明确保留一键登录：未登录时进入原 WelcomeView，仍需点击登录按钮；已有会话沿用原有路由。接口不可用不会让启动动画一直等待。
- 启动状态属于稳定的 SwiftUI Host；仅背景延伸到安全区外，图标相对当前安全区域居中，不依赖设备屏幕常量。进入首页后，前后台切换不重新展示启动页；暂停于启动期间则取消并在回到前台时恢复短过渡。没有新增 scene、摄像头或支付所有者。
- 使用 UI 长期规范、UI Taste 简化/iOS/craft、Claude Design 设计方向、Duo 和 Garden / Image 2 Host-Native 工作流；保留原 ClipoMark/AppIcon。新增圆角透明展示副本 `ClipoLaunchMark.imageset/clipo-launch-mark.png` 与原创 loading 资产 `ClipoLoadingMark.imageset/clipo-loading-mark.png`，均位于 `Clipo/Resources/Assets.xcassets/`。提示词保存在 `ProjectMaterials/UIAssets/Prompts/clipo-launch-mark.txt` 与 `clipo-loading-mark.txt`。
- 本次检查了图片、透明通道、plist/JSON/XML、Storyboard 资源引用与 target 归属、git diff。此次 UI 增量未编译、未运行模拟器/真机、未实际渲染启动页，未验证 Duo 姿态；下方此前的 BUILD SUCCEEDED 仅针对此前版本。
- Apple 依据：[Launching](https://developer.apple.com/design/human-interface-guidelines/launching)，系统 Launch 与首个应用界面保持一致；本项目按照用户要求保留启动图标。

## 界面视觉整理（2026-10-19 后续增量）

- 方向：低饱和炭黑底色、浅鼠尾草色操作面板、单一荧光绿强调。品牌保留圆角字标，正文与标题使用支持 Dynamic Type 的原生字体；缩短大段宣传文案，操作优先。密度 5/10、动效 1/10，不新增装饰动画。
- 登录页：缩小品牌标记，精简标题，三条功能说明；一键游客登录为主操作，本地编辑为次操作。启动页仍保持中央图标与 loading，结束后走原有登录/会话路由。
- 首页：独立浅色链接输入面板、深色打开按钮，粘贴与密码操作可在窄容器换行；浏览和剪辑入口分组。错误文本保留在深色背景，避免浅底上的红色低对比。
- Studio：紧凑的导入面板、清楚的 Photos/Files 入口；预览从固定 300pt 高度改为跟随可用宽度的 4:3 容器，视频仍保持原比例适配。工具栏和导出处理没有更换数据源。
- Library：清晰的 Saved/Imports/Exports 分类、真实本地条目数和对应空状态；删除确认支持滚动与 medium/large 系统弹层尺寸。
- Plus：浅色权益区域、Apple 商品名称/周期/本地价格方案行；广告补充额度单独呈现。恢复购买与重试验单入口保留，未更改支付、奖励或权益判断。
- 底栏：收紧图标间距与高度，独立深色导航容器，选中状态保留位置标记和辅助功能语义。沿用原生 safeAreaInset，占位不覆盖页面内容。
- 容器适配：主要工具页最大宽度 680pt、登录页 560pt、导航内容 480pt，均是本项目阅读宽度选择，不是假定设备尺寸。尺寸变化只影响布局，没有添加尺寸驱动的 id、登录或购买调用。未声称完成 Duo 折叠区域、遮挡及姿态实测。
- 技能：UI Design Reference、UI Taste 的 iOS/craft/polish、Redesign、Design、Duo；评估 Taste/Claude Design/Garden 范围后复用既有原创图像，没有引入 Web 实现、系统图标或代码绘制的替代美术。
- 静态检查：git diff 空白检查通过；图像引用全部存在，资产 Contents.json/图片文件及 Info.plist 可读。色值计算中次级文字/深色面板为 7.77:1，次级文字/raised 为 6.59:1，浅底次级文字为 6.00:1。数值不替代实际屏幕、VoiceOver 或大字体运行验收。
- 此次未编译、测试、启动 App/模拟器或执行服务验证；此前编译成功不覆盖这次 UI 改动。未对实际页面截图作视觉验收。

### 底栏点击与样式修正

- 根据用户实际截图，替换双层胶囊底栏为平整底色、细分隔线、四个等宽按钮；原创图标缩至 size=21，当前项以荧光绿图标和 48×44pt 淡色底标识，不增加文字或新图像素材。
- 新的 `ClipoTabBar` 在每个 60pt 高按钮 label 的最终布局之后指定 `.contentShape(.interaction, Rectangle())`。图标、选中底色和分隔线不参与命中，点击范围由按钮完整单元格拥有。
- 共享 Glyph 内的四倍图集不再参与点击判定，图标外层限定为当前裁切单元格；共享 IconButton 明确声明 48×48pt 热区。这覆盖了原代码中图集越界命中及透明留白没有明确热区的风险，尚未通过运行确认用户报障的唯一根因。
- 四个按钮沿用原先 tab 状态及编辑项清理回调，safeAreaInset 保留；没有新增登录门槛、遮罩手势或尺寸驱动的页面重建。
- 已核查源码按钮路由、装饰层命中设置及 git diff；未编译、未启动模拟器、未执行真实点击或视觉截图验证。待运行验收：四个图标中心及周围留白点击、Studio → Home → Discover → Library 往返、窄宽容器与大字体。
- 官方 API 依据：[interaction](https://developer.apple.com/documentation/swiftui/contentshapekinds/interaction)、[allowsHitTesting](https://developer.apple.com/documentation/swiftui/view/allowshittesting(_:))。

### TabBar 原创图片版本（替代上面的绘制型选中状态）

- 按用户最新要求，用 Garden / Image 2 Host-Native 内置生图工具重新生成 8 张独立透明 PNG：Home、Discover、Studio、Library 各包含 Normal/Selected；选中底片与深色图形已一起生成在 Selected 图片内。素材已经复制入 `Clipo/Resources/Assets.xcassets/TabBar/`，无外部临时路径依赖。
- 每张 PNG 为 1254×1254 RGBA，imageset 设置 original rendering。没有通过 Python/SVG/Canvas/Core Graphics 绘制或修图；脚本仅复制文件、写资源描述和读取元数据。
- 8 份提示词与生成来源清单位于 `ProjectMaterials/UIAssets/Prompts/TabBar/`。初始默认态分别原创生成；选中态以默认图形为编辑目标，并以 Home 选中底片作为一致性参考。
- `ClipoTabBar` 直接显示 64×64pt PNG，替代原 Glyph 图集、tint、RoundedRectangle 背景及分隔线。除普通页面底色外，可见的 Tab 图形与选中装饰全部来自图片。
- 每个按钮保留等宽、68pt 高原生热区及 accessibility 标记。`Color.clear` 是不可见布局占位，`contentShape(Rectangle())` 仅定义触摸范围，不会绘制矩形；图片不接管触摸，原 select(item) → tab → 四个页面路由保持连接。
- 已目视检查 8 张生成素材，核对 alpha、尺寸、资源目录/名称、现有 xcassets target 归属及源码路由，git diff 空白检查通过。未编译、未运行模拟器/真机或做实际点击验收；静态检查不等于运行确认。

## Google 官方测试广告

当前 `Config/Clipo.xcconfig` 的 `CLIPO_ADS_TEST_MODE = YES`，Debug 和 Release 均按此显式开关使用测试广告，便于先做内部测试。

- iOS 测试 App ID：`ca-app-pub-3940256099942544~1458002511`。
- iOS 激励测试广告单元：`ca-app-pub-3940256099942544/1712485313`。
- 测试模式只允许上述官方 App ID 和广告单元，不依赖后台 adList，不使用后台下发的正式广告。仍需一键登录，额度按现有用户保存；不会创建虚假游客或绕过奖励回调。
- 官方 demo App 没有 Clipo 自有 UMP 消息配置，因此此限定分支不发起 UMP 同意请求；正式模式完整保留 UMP 门控。测试广告不代表正式 UMP 流程验证通过。
- 测试入口：一键登录 → Clipo Plus → Watch ad for more views。完整观看后由 SDK 的奖励回调增加额度，提前关闭不主动发奖，加载失败不发奖。阈值和 adType=2 不变。
- 已添加 Google 的 SKAdNetwork 标识；发行前再按实际广告来源补齐第三方列表。
- 上线前切换开关并替换正式 ID；本次未运行 App、未实际加载/播放测试广告。

官方来源：[iOS SDK 配置](https://developers.google.com/admob/ios/quick-start)、[iOS 测试广告](https://developers.google.com/admob/ios/test-ads)。

## 已做与未做的验证

已做源码/配置/资源静态检查（接口原文保留既有尾随空格）：plist 和 pbxproj 可解析，Swift 文件与资源显式 target 归属、资源文件存在、原始资料排除、主域名与ID一致、素材尺寸、JSON 结构、差异与空白检查、交易结束顺序人工检查。首版盘点为15个Swift源文件、3项显式资源引用、源资源约2.59 MiB；新增启动 Storyboard 后现为4项显式资源引用并增加两张图像，旧资源体积不代表当前包大小。

2026-10-19 按用户本次授权执行编译：Xcode 27.1（27A9275），Clipo scheme / Debug / generic iOS arm64，关闭签名。修复视频编辑器 CMTimeRangeGetIntersection 缺少 otherRange: 标签后，xcodebuild 返回 0，结果为 BUILD SUCCEEDED。此前 fraction、播放器闭包显式 self、QuotaStore 的 catch 变量遮蔽问题未再报错。构建日志仅剩未依赖 AppIntents.framework 而跳过元数据提取的工具提示，无源码编译错误。

复现命令：

```sh
xcodebuild -project Clipo.xcodeproj -scheme Clipo -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath /tmp/clipo-build-check/DerivedData CODE_SIGNING_ALLOWED=NO build
```

本机编译日志：`/tmp/clipo-build-check/debug-build.log`（临时文件）。未执行自动测试、模拟器/设备或 App 启动、真实界面渲染、业务接口请求、StoreKit 沙盒购买/恢复、广告播放、视频解码/导出实测，也未验证 Release Archive 或发行签名。编译通过不等于这些运行与发行验证通过。

## 参考

- Figma：https://www.figma.com/design/LbCyJ0BI2CUGKzjw5fBTgD/LT-%E5%AF%B9%E6%8E%A5-UI?node-id=198-2270
- 接口原文：本目录 API-reference.md（保留用户提供内容，不将文档示例当成本次配置）。
- Apple AVFoundation 编辑：https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/AVFoundationPG/Articles/03_Editing.html
- Google 官方激励广告：https://developers.google.com/admob/ios/rewarded
- Google 官方 UMP：https://developers.google.com/admob/ios/privacy
- Google 官方 SPM：https://github.com/googleads/swift-package-manager-google-mobile-ads

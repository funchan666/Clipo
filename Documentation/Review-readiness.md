# Clipo：本轮修改与提交审核风险

更新：2026-10-21。此记录基于当前源码、配置、资源和 Apple 公开规则。没有编译、运行测试、启动模拟器、购买、请求线上内容或发布新包；不能据此承诺审核通过。

## 已完成

1. **本地字体**：Barlow Regular / SemiBold 用于正文与操作文字，Lora 用于网球主题的编辑式标题。3 个字体文件合计 424,612 字节，随安装包加载，不运行时下载。保留 OFL 许可证；阿拉伯语、日语和韩语缺失字形使用系统字形回退，未强行替换为不完整字体。支持 Dynamic Type，真实系统购买/权限界面不改造。
2. **发球训练记录**：工具页新增 Serve practice。选择平分区/占先区及外角、追身、T 点，记录命中目标、界内偏离、下网、出界。支持撤销、结束训练、历史记录、各区域目标命中统计、删除单次训练和 CSV 导出。逐次落盘，写入失败不假装保存成功；数据损坏时保留原文件。结果基于手动记录，没有虚构 AI 动作识别、球速识别或医疗建议。
3. **原创画面**：新增球场、球拍、训练笔记与计数器插画，使用 Garden / Image 2 Host-Native 工作流生成；提示记录在 `ProjectMaterials/UIAssets/ServePractice/brief.md`。新功能沿用已有原创位图按钮，文字原生渲染并覆盖七种语言。UI 工作应用了 ui-design-reference、ui-taste、impeccable、gpt-image-2 和 Duo；未套用网页技术栈。
4. **权限处理**：系统视频/文件选择器取消时安静结束；没有新增权限前置提醒、拒绝后追问或自动打开设置。协议 WebView 明确拒绝与其用途无关的网页相机/麦克风请求。相册保存用途说明更新为用户主动导出的网球练习视频，覆盖七种语言。补充 UserDefaults 必需理由声明 CA92.1。
5. **资源整理**：Assets.xcassets 从 42,076,051 字节降至 10,500,656 字节，约减少 75.0%。13 组未使用素材移至非打包的原画档案；三个不透明插画以原尺寸 JPEG 92 保存；10 个 Tab 图缩至 252px；其余按钮/透明/图集使用无损 PNG 优化，逐像素核对未变化。App Icon 保持原样。完整原画备份在 `ProjectMaterials/ArtworkArchive/2026-10-21`。这是素材目录大小，不是 IPA、下载或安装大小；未加工 Assets.car。原演示录像不属于 App 资源，没有重压用户留存的录像。
6. **业务命名**：模型明确为 LessonClip、RemoteLessonFile、RecommendedLesson、LessonFeedPage、PracticeRecording、LessonLibrarySnapshot、LessonLinkVisit；源码文件改为 LessonContracts / PracticeVideoWorkspace。下载额度明确为 dailyDownloadLimit / downloadRewardCount，CodingKeys 保留后端旧键 unlimitedAfterAdCount / favoriteBaseLimit。收藏、离线索引、付款账本等持久化键和服务端字段不随改名变化。资源文件使用 court、serve、player、tab 等实际用途名称。工程是原生 Swift，没有 Flutter 的 lib/assets 目录；保留 Apple 的 Resources/Assets.xcassets 规范。
7. **会员不改**：不做金币钱包，不改月/年会员商品、美元参考价、订单归属及恢复保护，不发放虚假购买权益。

## 审核评估与剩余风险

### 4.3：真实差异化

已有功能包括网球课程短链、竖屏教学播放、收藏、独立离线下载额度、练球视频剪辑/变速/重构画面/提取音频、离线网球知识、发球记录与统计。新增训练记录形成“看教学—练习—复盘”的实际用途，不是签到或抽奖。

仍不能宣称没有 4.3 风险：公开规则关注实际体验和重复提交，Apple 不公开 Framework 或 Assets.car 相似度阈值。没有计算或伪造所谓机审通过率。使用同一系统框架、Google SDK、合理类名本身不能证明违规，也不能靠随机改名、混淆或单独开发者账号保证通过。此轮只做可维护的命名、真实功能与资源精简，没有插入审核识别、审核专用内容或运行时换壳代码。

**提交前仍需实际验收新功能、填写真实产品描述、提供持续可用的网球课程和审核短链。** 原录像早于此次修改，不能当作本轮验收证据。

### 1.1.4 / 1.2：内容

本地界面、七语言文案与自带知识内容未发现明显色情、约炮、赌博或虚构社交活动。当前没有应用内公开发帖、评论、聊天、用户视频上传或生成虚假用户的功能；练习视频和发球记录由用户本人管理。

但 **远端搜索、短链返回的视频/标题/封面无法仅靠客户端源码保证合规**。当前接口是通用媒体模型，没有可信的网球分类、版权或审核结果字段。不能用关键词黑名单冒充视频审核，也没有在本轮伪造举报已提交。发布方需要提供经过筛选且有授权的网球内容和持续处置能力。若实际接入外部创作者/用户内容，须按 1.2 落实内容过滤、举报受理、屏蔽滥用者及可用联系方式；现有接口没有完整支持这些服务端能力。

### 已确认但仍存在的发布限制（不是重复询问产品需求）

1. **游客账号删除**：你已明确不做删除入口，本轮未添加。当前确实会向服务器创建游客并持有 userId；没有删除接口。因此仍需由发布方承担 5.1.1(v) 相关风险，不能仅把账号叫“游客”就视为无账号。
2. **会员恢复**：你已确认后端不关联缺失原订单。现有恢复入口保留，但重装/换身份后缺少原始归属时不会擅自授予会员；这是一项订阅恢复能力限制。没有为绕过限制移除归属保护，也没有改会员方案。
3. **Apple 商品登记**：两个商品仍是自动续订月/年会员，ID 分别 coins_1.99、conis_4.99，UI 参考 US$9.99/US$99.99，购买时取 Apple 实时商品；名称中的 coins 不代表实现了金币。登记、可售状态、订阅组、价格、真实购买及恢复尚未在本轮验证。
4. **协议和联系方式**：资料已确认（2026-10-22）：邮箱 support@clipo.vip、运营主体 Clipo、生效日期 2026-10-22、最终 Icon 使用当前版本。正式协议链接已配置；历史本地协议草稿仍有占位内容，不能直接作为正式协议发布。协议还应准确说明自动游客登录、广告、搜索信息与本地练习记录的实际处理。
5. **广告和隐私**：按确认保留 Google 官方测试广告及现有 UMP 流程，正式广告等你确认首版审核通过后再配置。没有声称 Google SDK 最终收集行为已经通过真机核验；App Store 隐私标签需要和提交包中的 SDK/后台事实一致。测试广告不能证明生产广告已可用。
6. **后台安全/最小化收集**：现有契约包含键盘输入语言列表、时区及安装标识；需要后台确认必要性和披露。`iosVerifyShareKey` 若为真正的 Apple 共享密钥，应由服务端保管，不应下发客户端。此轮没有破坏已确认接口或付款契约，亦未把敏感数据写入报告。
7. **推荐内容**：你已确认空列表是后台暂未配置视频，不作为开发阻塞；正式提交时应有真实可用内容及访问样例。没有用素材冒充推荐视频。

以上既有决定保持不变。可继续独立处理的源码工作已做；是否改变上述发布限制由你决定，不再向甲方追问已经解释过的广告字段或额度规则。

## 权限入口逐项核对

| 入口 | 当前实现 | 拒绝/取消处理 |
| --- | --- | --- |
| 导入视频 | PhotosPicker，用户选择的视频 | 无全相册申请；选择器取消不显示追加提示；传输取消安静返回 |
| 浏览文件 | fileImporter，安全作用域文件导入 | 用户取消不弹错误，不跳设置；真实文件读取失败保留错误说明 |
| 导出视频 | 本机导出后系统分享面板 | OS 管理分享/存入照片；App 不接管或模仿系统权限弹窗 |
| 相机/麦克风 | 无原生采集功能、无授权请求 | 不新增权限用途或设置跳转 |
| 协议网页 | 非持久 WKWebView | 网页媒体采集一律拒绝，因为协议阅读不依赖采集 |
| 新训练记录 | 手动计数、本机存储、CSV 分享 | 不申请相机、麦克风、照片、位置权限 |

全局没有找到 App 自己调用 openSettingsURLString、PHPhotoLibrary.requestAuthorization 或 AVCaptureDevice.requestAccess 的入口。因此不添加无实际用途的“权限管理器”或二次追问。若以后新增必须依赖权限的功能，再按“首次拒绝安静结束；后续用户主动触发且权限已锁定时提供中性、可取消设置入口”实现。

## 自适应与检查边界

新增训练页使用容器宽度、可滚动内容、adaptive grid、ViewThatFits、原生动态字体及现有安全区处理。记录状态不以屏幕宽度为 id，不因尺寸变化重新登录或重建训练存储。没有硬编码 Duo 屏幕尺寸或声明未经 SDK 核实的折叠 API。

已完成静态核对：22 个 Swift 文件均已登记到工程；23 个资产集合引用完整；七种语言各 444 个唯一键一致，已移除重复键；3 个字体的 PostScript 名称与加载代码一致；工程/plist/strings/JSON 可解析，git diff 格式检查通过。无损 PNG 已核对 RGBA 像素相同，压缩后的新插画和 Tab 素材已目视检查。以上检查未执行 Swift 编译或测试。

未完成：编译、模拟器/真机、Duo 内外屏与折叠遮挡、多语言大字体实际截图、断电/低存储、CSV 分享、视频播放/下载、真实广告、真实购买/恢复、后台内容审核与最终 App Store 提交检查。静态资源和路径通过不代表上述运行行为已验证。

## 官方依据

- [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)：重点参考 1.1.4、1.2、2.1、3.1.2、4.3、5.1.1(v)。本报告中的风险等级是项目判断，不是 Apple 审核结论。
- [Apple Privacy HIG](https://developer.apple.com/design/human-interface-guidelines/privacy/)：权限应结合真实用途和用户操作，不强迫授权。
- [Photos picker](https://developer.apple.com/videos/play/wwdc2023/10107/)：使用系统选择流程取得用户选择的媒体。
- [WKWebView 媒体权限代理](https://developer.apple.com/documentation/webkit/wkuidelegate/webview(_:requestmediacapturepermissionfor:initiatedbyframe:type:decisionhandler:))：协议页的相机/麦克风拒绝策略。
- [Required reason API](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)：UserDefaults CA92.1 用于应用自己的偏好数据。
- [Barlow](https://github.com/google/fonts/tree/main/ofl/barlow)、[Lora](https://github.com/google/fonts/tree/main/ofl/lora)：字体来源，完整 OFL 许可证随字体保留。

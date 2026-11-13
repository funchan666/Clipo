<!-- appstore-review-audit-report:v1 -->
# App Store 首审风险审计

项目：Clipo IPA 审核风险审计

审计日期：2026-11-12；技能版本：1.2.0

版本/工作区：未审计源码或建立源码与 IPA 的构建对应关系

Target：Clipo 1.0.1 build 9 / com.cliporows.toolskeep / arm64；配置：用户提供的 IPA，实际提交及签名配置未经确认

审计范围：只读检查所提供 IPA 包体、plist、英文资源、隐私清单及有限二进制字符串；未运行 App、访问业务接口或审查 ASC/后台。

规则核验：在线核验；日期：2026-11-12

> 本报告由已脱敏的输入生成。渲染成功仅说明数据形状有效，不证明证据真实、条款适用或能够过审；渲染器不代替脱敏检查。

## 结论

在本次有限包体静态范围内未确认 P0/P1；不能据此判断没有 P1。视频授权、订阅交付、广告隐私、审核访问及账户模型需要补证。Hopper 逆向未完成。

活跃风险共 0 项（P0：0，P1：0，P2：0，P3：0）。

其中已确认 0 项；高度疑似 0 项；待核验 0 项。

历史项目 0 项、代码外待补证 8 项，均不计入上述活跃风险数。

## 覆盖范围

- 发布配置 · 已检查：仅检查 IPA：Clipo 1.0.1 \(9\)，com.cliporows.toolskeep，最低 iOS 17，设备 arm64，SDK 标记 iPhoneOS 27.1；无签名有效性或 ASC 校验。SHA-256 e7cfd7d1d24cf675c80e094ec39b332bbee8e1af5c618b62a24f80af60f14613。
- 二进制与逆向 · 待补证：主程序 arm64 UUID 3E548CB5-610B-3D85-BC92-6D9A579129E5，LC\_ENCRYPTION\_INFO\_64 cryptid=0；两个内嵌 framework 的 arm64 slice 均 cryptid=0 且 cryptsize=0；不代表全部逻辑可读。REA MCP 选中 Hopper 打开主程序，但 120 秒初始化超时，未取得函数伪代码、交叉引用或指令；关闭会话返回 cleanup\_incomplete，临时资源仍保留，不能宣称已完成逆向。
- 启动/完整性 · 待补证：仅见启动及网络错误文案和配置；未启动 App，未核验生产服务、审核访问、崩溃或断网行为。
- 账户 · 待补证：文案提及账户与会话；没有匹配源码或运行证据，无法确定是否支持账户创建及删除义务是否适用。
- 隐私 · 待补证：检查主包及两个 SDK 隐私清单、Info.plist 与英文资源；真实数据流、广告设置、ATT 和 ASC 隐私标签未核实。
- 支付 · 待补证：Commerce.json 列出月/年订阅商品；可见 StoreKit 及恢复购买文案，未建立调用链或验证 ASC 与沙盒交易。
- 内容安全 · 待补证：包内视频、链接与分享文案不足以判定是否开放用户生成/发布或是否适用 1.2。服务端内容与功能不可见。
- Web/远程行为 · 待补证：可见 API 主机配置、WKWebView 相关符号和网络错误文案；未访问业务接口，无法验证服务器分组、加载内容与跳转。
- 依赖/平台API · 已检查：识别 GoogleMobileAds 和 UserMessagingPlatform 框架及各自清单；未能完成 SDK 内部行为或追踪归因。
- 产品/版权 · 待补证：文案显示远程视频可离线观看/下载及导出，未取得实际来源、授权和服务条款。
- Duo · 待补证：Info.plist 声明 portrait，SDK 标记 27.1；缺源码和实际 UI，不足以判断布局、折叠遮挡、播放和输入状态连续性。未做设备测试。
- 提交材料 · 待补证：未取得 ASC 隐私标签、截图、描述、年龄分级、订阅配置、审核备注与支持页面。

“已检查”表示完成所述范围的检查，不是认证通过。

## 官方来源核验记录

仅获取页面或 HTTP 请求成功不等于已阅读并核验。

- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)；日期：2026-11-12；状态：已阅读并核验；范围：1.2、2.1、3.1.2、5.1.1、5.2.2–5.2.3，按适用前提核对
- [App Review](https://developer.apple.com/distribute/app-review/)；日期：2026-11-12；状态：已阅读并核验；范围：审核信息及准备
- [User Privacy and Data Use](https://developer.apple.com/app-store/user-privacy-and-data-use/)；日期：2026-11-12；状态：已阅读并核验；范围：SDK 披露和追踪许可
- [Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)；日期：2026-11-12；状态：已阅读并核验；范围：隐私清单
- [Prepare your app for iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111461/)；日期：2026-11-12；状态：已阅读并核验；范围：SDK 与尺寸/安全区适配；技术指导非自动视作审核强制条款

## 活跃风险

本次输入没有活跃风险记录；结合覆盖范围与补证缺口解读，不等于保证过审。

## 代码外待补证

优先级表示潜在影响，以下缺口不是已确认风险。

### GAP-001 · P1

视频来源及下载、转换权限是否足够？

需要的证据：英文 Localizable.strings 含 Download for offline、下载流后导出及音频提取等文案，实际入口与远端内容未验证；确认全部内容来源、流媒体许可、下载/离线/转码及分发授权，必要时限制功能并准备可提供给 Apple 的授权。Apple 5.2.2、5.2.3。

负责角色：内容/后台/产品

### GAP-002 · P1

订阅购买、恢复与服务器权益能否完整交付？

需要的证据：Commerce.json 含 clipo.plus.monthly 和 clipo.plus.yearly；英文资源有恢复、待确认和错误文案，不能证明流程可用。核对 ASC 商品、地区、价格及版本关联，沙盒实测购买、取消、恢复、跨设备和网络中断后的权益与补偿；Apple 2.1\(b\)、3.1.2。

负责角色：iOS/后台/ASC

### GAP-003 · P1

广告实际数据使用是否构成 Apple 定义的 tracking，披露和许可是否一致？

需要的证据：主包 PrivacyInfo.xcprivacy 声明 NSPrivacyTracking=false；GoogleMobileAds 自带清单含设备 ID tracking=true。主包 Info.plist 未见 NSUserTrackingUsageDescription。SDK 声明是能力/披露线索，不能单独证明该构建实际 tracking 或缺少授权违规。核实广告配置、流向、实际隐私报告及 ASC 标签；如确有 tracking，先获得 ATT 授权并配置用途文案，禁止未授权追踪。

负责角色：iOS/广告/隐私

### GAP-004 · P1

审核员能否打开远程内容及所有关键功能？

需要的证据：只有包内主机配置、错误和登录/会话文案，没有运行或后端证据。用待提交 build 验证审查地区网络、启动、播放、离线、协议与需要的测试账号；必要时在审核备注提供路径。Apple 2.1。

负责角色：后台/iOS/ASC

### GAP-005 · P1

是否支持创建账户以及是否能够删除？

需要的证据：资源包含账户设置和会话文案，未能确认注册或删除入口、匿名身份的具体定义与后台删除结果。若支持账户创建，按 5.1.1\(v\) 提供应用内发起删除并验证服务端数据处理；否则记录账户模型依据。

负责角色：产品/iOS/后台

### GAP-006 · P2

隐私政策、条款、ASC 标签是否准确可访问？

需要的证据：Info.plist 有隐私与条款地址，主包和 SDK manifest 有不同数据类型声明；未访问应用网页或 ASC，核对入口、可访问性、收集用途、第三方披露及语言；Apple 5.1.1。

负责角色：隐私/ASC

### GAP-007 · P2

是否存在 UGC 或社交内容以及相应保护？

需要的证据：播放、分享及输入链接的文案不能证明用户可以公开上传或互动。若开放 UGC，验证过滤、举报、屏蔽、及时处理与联系方式；否则记录内容模型与适用性；Apple 1.2。

负责角色：产品/内容运营/后台

### GAP-008 · P2

Duo 设备上的布局和状态是否连续？

需要的证据：使用匹配源码检查容器尺寸、不对称安全区、遮挡、导航、键盘和播放/输入状态；经授权后在 Duo 不同姿态及分屏验证。portrait 声明不足以判定缺陷。

负责角色：iOS

## 已解决与不适用历史

本次无历史项目。

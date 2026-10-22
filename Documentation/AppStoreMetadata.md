# Clipo App Store 资料

英文名称，21 个字符。应用描述 2795 个字符。正文使用普通英文与标点，无装饰符号和表情。

## Bundle ID

优先使用已确认的 com.cliporows.toolskeep。其他候选需先确认可注册并创建相应 App 记录，不包含 Git 用户名。

com.cliporows.toolskeep
com.clipo.tennispractice
com.clipo.courtnotes
com.clipo.practicevideo

当前项目实际 Debug 和 Release Bundle ID 仍为 im.seex.lobo，未切换正式签名身份；本轮仅使 xcconfig 后备值与该实际值一致。不要将不同 Bundle ID 的商品、配置和签名混用。

## 应用名称

Clipo Tennis Practice

## 应用描述

Make more of the time between tennis sessions. Clipo brings shared lesson links, practice footage and court notes into one place, so an idea you discover can become something you work on next time you play.

Open a lesson link or code shared with you, search for videos and move through available lessons with a swipe. Keep useful clips in Favorites and return to the details you want to review. Lesson availability depends on the links and content provided through the service.

Bring in your own practice video from Photos or Files. Trim a clip to the moment that matters, adjust playback speed, rotate the picture and choose a frame that suits your review. Slow down a serve, take a closer look at footwork or keep a short sequence for your next practice. Your original media stays unchanged. Audio extraction is also available for supported videos.

Keep Favorites, offline videos, imported footage and media exports organized in separate Library sections. Cache supported lessons for playback without a connection and manage the local copies you keep on your device. Viewing and download allowances are shown in the app, with progress and status information when you save a video.

Give your serve practice a clear focus. Choose the deuce or ad court, aim wide, at the body or down the T, and record where each serve lands. Review target hits, serves in the service box, net errors and misses. Undo the last entry, revisit completed sessions and export a session as CSV. Placement results come from your own entries rather than automatic motion or ball tracking.

Read concise tennis field notes covering forehand, backhand, serving, scoring and the major tournaments. The notes are available offline, with links to further reading when you want more context. Bring a useful lesson shared by a coach or practice partner into your own routine, then use your footage and records to decide what to focus on together next time.

Clipo follows your system language where supported and offers English, Korean, Japanese, Indonesian, Portuguese, Arabic and Spanish. You can also choose a language in the app.

Free access includes daily viewing and download allowances. Where available, optional rewarded ads provide additional allowances. An optional Clipo Plus subscription includes unlimited viewing and downloads, along with media export. Video and audio exports require an active Plus membership. Supported media formats and source availability apply.

Subscription prices and billing periods are shown using the product information returned by Apple before purchase. Subscriptions renew automatically unless canceled through your Apple account. Restore Purchases is available in the membership screen.

Terms of Use: https://www.clipo.vip/#terms
Privacy Policy: https://www.clipo.vip/#privacy

## 测试账号与审核访问

账号和密码：不需要。当前应用使用服务端游客会话，没有账号密码登录表单；用户 ID 765732 不是可登录的审核账号。

No username or password is required. The app starts an authenticated guest session automatically. Open Tools to review an imported practice video, read Tennis field notes or use Serve practice. Open Get Plus to view subscriptions.

审核需要由后端提供持续可用的网球课程链接或短码，不能用虚构账号代替访问资料。最近生产 getV2 查询已成功；用户已向后端确认 iosVerifyShareKey 可不传，客户端已允许缺少 ios 配置，并在无校验值时省略该参数。实际购买和恢复仍待运行验证。

## 用户协议

https://www.clipo.vip/#terms

## 隐私协议

https://www.clipo.vip/#privacy

## 内购填写资料

两项均为自动续订会员，放入同一个 Clipo Plus 订阅组，提供相同会员权益。

| 项目 | 第一项 | 第二项 |
| --- | --- | --- |
| 商品 ID | clipo.plus.monthly | clipo.plus.yearly |
| 参考名称及英文显示名称 | Clipo Plus Monthly | Clipo Plus Yearly |
| 描述 | Unlimited views, downloads and media exports. | Unlimited views, downloads and media exports. |
| 订阅周期 | 1 month | 1 year |
| 确认的美元定价 | 9.99 | 99.99，全年预付 |

两个显示名称分别为 18、17 字符，描述均为 45 字符。以上为正式商品资料。当前客户端按用户要求临时使用 coins_1.99、conis_4.99 联调，测试通过并经用户确认后恢复表内商品 ID；临时测试期间保留旧商品的后台支持。界面实际显示及交易金额以 Apple 返回的本地化商品信息为准。本轮未运行商品加载、购买或恢复验证，后台商品映射尚待管理员同步。

## 真实内购检查

共享 Scheme 无本地 StoreKit 配置文件，源码无 StoreKitTest、SKTestSession 或模拟交易路径。会员页使用 Apple 返回的 SKProduct 显示名称、金额和周期，真实交易由 SKPaymentQueue 创建，使用 Apple 收据交给生产服务器确认后刷新权益。没有使用参考价格伪造可购买商品。

App Review 使用 Apple 沙盒交易属于正常审核环境，区别于 Xcode 本地模拟。后端需支持审核沙盒及生产收据验证，不能因正式发布而一律拒绝沙盒收据。本轮没有执行购买或恢复测试。

## 官方限制依据

名称不超过 30 字符，描述不超过 4000 字符。
https://developer.apple.com/help/app-store-connect/reference/app-information/app-information
https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information
https://developer.apple.com/help/app-review/before-submitting-for-review/configure-in-app-purchases

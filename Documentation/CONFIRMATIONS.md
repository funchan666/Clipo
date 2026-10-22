# Clipo 当前确认事项

更新于 2026-10-22。历史资料已从工程移出，以下保留有效结论。

## 品牌与生产资料

- 最终 Icon 使用当前 App Icon，运营主体 Clipo。
- 官网 https://www.clipo.vip，联系邮箱 support@clipo.vip，协议生效日期 2026-10-22。
- 用户协议 https://www.clipo.vip/#terms，隐私协议 https://www.clipo.vip/#privacy。
- API https://b8pd8t.clipo.vip，业务包名 com.cliporows.toolskeep，getV2 的 name 为 Clipo。
- 实际 Debug 和 Release 打包 Bundle ID 仍是 im.seex.lobo。xcconfig 与目标值已对齐；未切换签名身份。正式提交前必须匹配实际 App Store Connect 记录。
- AdMob App ID ca-app-pub-4423220037289714~4213264017 已写入安装包配置。开屏和激励广告位从 getV2 取得，无缺失配置时的本地测试广告兜底。App ID 与接口必须一致。

## 已确认的业务约定

- 不做金币钱包。用户已创建 Clipo Plus 订阅组及两项自动续订商品，并授权同步客户端：clipo.plus.monthly（月付，9.99 美元）、clipo.plus.yearly（年付，99.99 美元，全年预付）。两项提供同级 Plus 权益；界面的名称、金额及周期仍以 Apple 实际商品为准。
- Commerce.json 已同步新商品 ID；usdPrice 999 和 9999 保留原后端订单契约。StoreKit 查询和新订单 rightsName 使用新 ID，不修改 Keychain 中历史订单的商品 ID、订单号、归属和验单配置。
- 后台待同步商品映射：clipo.plus.monthly 对应月度 Plus、usdPrice 999；clipo.plus.yearly 对应年度 Plus、usdPrice 9999。用户已明确确认旧商品配置可以删除，仅保留这两项新商品；此确认不涉及清空设备交易队列或历史订单。当前没有后台管理写入入口，尚未修改生产后台。
- VIP 才能导出媒体，覆盖播放器、资料库、视频编辑和音频导出；发球记录 CSV 不属于媒体导出限制。
- 收藏不扣下载次数。观看与下载额度独立；getV2 的广告奖励立即更新，已消耗的每日基础额度配置次日生效。完整广告推进奖励轮次，幸运奖励不推进。
- 额度耗尽后主动获取奖励时，广告配置不可用、同意配置或表单加载失败、无广告填充、加载超时和展示失败均走幸运奖励；使用当前阶段对应额度，持久化成功后展示奖励。取消加载或中途关闭已展示广告不发幸运奖励，重复回调不重复发放。开屏广告失败不发奖励。
- 无观看额度时，首次进入受限新视频提示一次；关闭后不循环弹出。主动切到受限新视频或点击获取更多次数时可再次提示。
- 每次冷启动真实游客登录，公网 IPv4 写入 uniqueId；IP 服务失败按原接口允许为空，不替代安装标识。
- 搜索通过 search-check。主动搜索成功但无可播放结果（包括成功响应 data 为 null）时，以原输入在 App 内 WKWebView 打开 Google 搜索，支持网页后退和关闭返回；新窗口链接也留在 App 内，阻止外部 App scheme。接口报错保留重试。推荐流耗尽重新开始会话。
- 两个协议和官网入口已配置；七种语言跟随系统，未支持语言回退英语。
- 播放器缓存与导出分开。支持的未加密 H.264 AAC TS VOD 可客户端封装为 MP4，不承诺任意 HLS 可导出，不绕过 DRM。
- 既定不做账号删除入口；后端不恢复缺失原订单关联。客户端继续保留原订单归属保护，不伪造删除、恢复或会员权益。

## 本轮检查及发布依赖

- 已检查真实 StoreKit 请求、支付队列、Apple 收据与服务端确认调用。共享 Scheme 没有 StoreKitConfigurationFileReference，工程无 .storekit 文件和 StoreKitTest 模拟商品依赖。
- 2026-10-22 同步商品时，使用用户提供的 765732 只读复查生产 getV2，name Clipo、platform IOS、version 1.0.0，已返回 code 0，取代此前“分发包不存在”的结果。但 data 没有 ios 购买配置，monthlyPayment、annualPayment、monthlyPrice、annualPrice 均为 null，尚不能据此认定真实购买可用。需后台补齐购买配置及新商品映射；客户端未向后台执行写入或下单。
- 应用自动创建游客会话，没有账号密码登录表单，因此不编造审核测试账号。审核备注应说明无需账号密码；还需准备真实可用的网球课程短码。
- Apple 审核及 TestFlight 使用 Apple 沙盒交易是正常流程，不等于 Xcode 本地模拟商品。服务端必须支持审核沙盒收据；本轮未改变 sandBoxTest 后端契约。
- 用户截图确认 Clipo Plus 组内已创建两项订阅，月度商品 ID 为 clipo.plus.monthly、周期为 1 month；客户端已按确认方案同步。Apple 实际返回的两项商品、年度详情、有效付费协议、Sandbox 购买和恢复尚未运行验证。不同 Bundle ID 下的商品必须属于对应 App 记录。
- 最新已存在 IPA 约 12.73 MB、解压 Payload 约 17.27 MB，均低于 50 MB；这些是旧包测量，不是本轮新包。
- 资源采用无损 PNG 重压缩，22 张图片与原图逐像素核对，尺寸、透明度及 ICC 保持一致。未降低 JPEG 品质或图片分辨率。
- 本轮仅静态检查和现有 IPA 内容检查，未编译、运行应用、下单购买、打包或上传。

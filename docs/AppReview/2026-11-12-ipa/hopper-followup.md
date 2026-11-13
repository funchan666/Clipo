# Hopper 逆向复核补充

日期：2026-11-12。对象：用户提供的 Clipo.ipa，Clipo 1.0.1 build 9，arm64 主程序；IPA SHA-256：e7cfd7d1d24cf675c80e094ec39b332bbee8e1af5c618b62a24f80af60f14613。主程序 SHA-256：5a522e09ffdcf532258605ec2f62801f3e0d68cf0d417a6c3145c87485be4f2b。

## 结论

重新使用 Hopper 演示模式完成后台分析，并对广告初始化和一个 StoreKit 交易处理函数进行局部伪代码及引用检查。此次局部复核未发现足以确认 P0/P1 的证据，也不能排除其他风险。原报告的视频授权、实际广告数据流、订阅权益及审核访问等待补证事项仍成立。

## 工具与范围

上次 REA MCP 的 Hopper 会话在许可证选择窗口等待，超时；本次进入演示模式后，REA 旧会话关闭仍返回 cleanup_incomplete。随后直接使用 Hopper 图形界面查看主程序，并非通过 REA 成功获取伪代码。Hopper 文件信息显示 unknown path，但其 arm64 入口地址 0x10002ea00、文件偏移 190976 与所提取主程序 LC_MAIN entryoff 一致；结合选择过程支持目标对应，仍非 Hopper 内哈希核验。Hopper 日志显示 11 轮后台分析完成，约 31,583 个识别的 procedure，识别数量不代表语义覆盖。文档为临时未保存分析，窗口保持打开；REA 临时资源关闭状态未确认。

## 已观察证据

1. 广告初始化：字符串 `prepareSDK(demoMode:mayPresentConsent:mayContinue:consentPresentation:)` 位于 0x100495530，交叉引用 0x1000d92f8 属于 `sub_1000d90c4`。Hopper 伪代码显示该函数不同条件分支中分别出现 `UMPConsentInformation` 的 `requestConsentInfoUpdateWithParameters:completionHandler:`（调用位置 0x1000d9440）与 `GADMobileAds` 的 `startWithCompletionHandler:`（调用位置 0x1000d9230）。这证明局部代码包含相关调用，不证明所有地区、状态下的顺序、同意结果、ATT 请求或实际追踪行为。分支条件是反编译器的低级状态和间接回调，尚未还原为可靠业务条件。
2. 交易处理：`finishTransaction:` selector 的 stub 0x1003f68c0 存在四处调用引用（0x10006a338、0x10006ba60、0x10006e8b0、0x10006f300）。其中 0x10006a338 位于 `sub_100069d24`，汇编显示通过 `SKPaymentQueue` 的 defaultQueue 发送 finishTransaction。该函数伪代码入口检查 `CommerceStore_ledgerAvailable` 与交易标识是否存在，条件不满足走退出分支；进一步的交易结束判断有其他条件。这里尚未追完其他调用方、账本持久化、服务端确认和错误恢复，不能据此认定支付顺序完全正确或错误。

## 剩余核验

- 使用匹配源码或可重复的完整逆向，追踪广告同意回调、状态含义、SDK 启动及 ATT 和数据流；核对 ASC 披露。
- 在沙盒与真实后台条件下验证购买、取消、恢复、网络失败和跨设备权益；检查每个 finishTransaction 分支与持久化/服务器确认的关系。
- 视频来源与下载授权、审核员访问、账户创建和删除、Duo 布局仍需原报告所列证据。没有安装或运行 App，没有调用业务服务，没有验证 ASC。

原报告：[review-report.md](review-report.md)。

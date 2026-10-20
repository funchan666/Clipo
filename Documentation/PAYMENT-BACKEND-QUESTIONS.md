# 可直接转发给后端的支付问题

Clipo 客户端已经接入创建订单、Apple 支付及购买成功验单。请补充下面三项契约，便于完成取消、恢复与沙盒联调：

1. `POST /app-api/flow/rights-order/buySuccess` 的 `status=canceled` 和 `status=error`，请各给一个真实请求示例。用户在 Apple 弹窗取消时可能没有 `transactionId` 和收据；此时 `verificationData`、`transactionId` 能否为空或省略？同一个订单重复上报如何处理？
2. 用户换手机、清空本地数据或重装后，客户端可能没有原后端订单号。能否通过 Apple `originalTransactionId`／收据查询原 `purchaseID` 及所属用户？请提供接口和重复验单的幂等规则；不能按当前账号或相同商品 ID 猜测归属。
3. 创建订单的 `usdPrice`，文档示例 `999` 和 `9999` 是“美分金额”、美元金额，还是固定套餐值？当前配置沿用这两个示例值，请明确单位／含义及与 Apple 注册商品的映射。

商品 ID：月 `ypsmwxmscbzeixig`，年 `xfpkaphmqxhtgzvx`。

这些问题不需要用户解释 Swift 或 StoreKit；需要后端确认接口含义。Apple 商品登记后仍需测试购买、取消、恢复与断网重试，文档或编译不能代替沙盒支付结果。

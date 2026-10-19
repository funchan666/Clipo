# 三方接口接入说明

> 本文基于当前项目源码、`API.md` 及接口封装整理。

## 1. 接入范围

当前代码中确认实际调用的业务接口共 10 个：

| 方法 | 路径 | 用途 |
|---|---|---|
| GET | `/app-api/flow/release-package/getV2` | 获取发布配置、广告和推荐配置 |
| POST | `/app-api/member/auth/app_tourist_login` | 游客登录、获取 Token |
| POST | `/app-api/flow/land-page/info_by_links_list` | 批量获取落地页/热门文件夹信息 |
| GET | `/app-api/flow/land-page/info_by_links` | 获取单个落地页或频道详情 |
| GET | `/app-api/flow/land-page/list_by_links_page` | 获取频道内容分页 |
| GET | `/app-api/flow/search-check` | 获取推荐/搜索视频 Feed |
| POST | `/app-api/flow/rights-order/buy` | 创建 iOS 权益订单 |
| POST | `/app-api/flow/rights-order/google/buy` | Android/Google 购买确认 |
| POST | `/app-api/flow/rights-order/buySuccess` | iOS 购买结果确认 |
| GET | `/app-api/member/user/get` | 查询用户资料和权益 |

以下接口目前仅保留在协议文档中，当前源码没有实际调用：


### 2.1 请求头

普通业务请求：

```http
Accept: application/json, text/plain, */*
Content-Type: application/json
Authorization: Bearer <accessToken>
```

说明：

- GET 请求通常不设置 `Content-Type`。
- POST 请求使用 JSON 请求体。
- 游客登录接口不携带 `Authorization`。
- 发布配置接口不携带 `Authorization`。
- 批量落地页接口当前代码显式不携带 `Authorization`。
- 默认超时时间为 15 秒。

### 2.2 通用响应格式

```json
{
  "code": 0,
  "msg": "success",
  "data": {}
}
```

| 字段 | 类型 | 说明 |
|---|---|---|
| `code` | `int` | 业务状态码，`0` 表示成功 |
| `msg` | `string` | 业务提示信息 |
| `data` | `object` / `array` / `string` / `null` | 具体业务数据 |

成功条件：

```text
HTTP 状态码为 2xx，并且 code == 0
```

`code` 缺失或类型错误时，客户端按失败处理。

### 2.3 401 处理

已认证请求返回 HTTP 401 时：

1. 重新执行游客登录；
2. 获取新的 `accessToken`；
3. 使用新 Token 重试原请求一次；
4. 不进行无限重试。



# 3. 详细接口

## 3.1 获取发布配置

```http
GET /app-api/flow/release-package/getV2
```


### Query 参数

| 参数 | 类型 | 必填 | 说明 |
|---|---|---:|---|
| `platform` | `string` | 是 | `IOS` 或 `Android` |
| `name` | `string` | 是 | `包名` |
| `version` | `string` | 是 | App 版本，不含构建号 |
| `lang` | `string` | 是 | 当前应用语言 |
| `userId` | `string` | 是 | `登录接口返回的userId字段值` |
| `time` | `string` | 是 | `手机时区` |
| `input` | `string` | 是 | `手机键盘` |

示例：

```http
GET /app-api/flow/release-package/getV2?platform=Android&name=appName&version=1.0.0&lang=en&userId=001
```

### 响应

```json
{
  "code": 0,
  "msg": "success",
  "data": {
    "NB01": false,
    "ios": {
      "iosVerifyShareKey": "string",
      "sandBoxTest": false
    },
    "quotaConfig": {
      "dailyWatchLimit": 5,    //每日基础观看额度
      "firstAdRewardWatchCount": 3,   //观看完第一个激励广告下发的基础额度
      "secondAdRewardWatchCount": 3,  //观看完第二个激励广告下发的基础额度
      "thirdAdRewardWatchCount": 3,  //观看完第三个激励广告下发的基础额度   当日观看完第四个激励广告后可无限次观看
      "unlimitedAfterAdCount": 5,   //每日基础收藏额度
      "favoriteBaseLimit": 5,  //每观看完一个激励广告下发的收藏次数额度
      "caption": "string",   //对应额度文案
      "icon": "https://example.com/icon.png"  //对应额度文案前面的icon
      //激励广告在对应额度消耗完后触发观看激励广告的弹窗，如果本次无激励广告返回，则触发幸运弹窗奖励，展示奖励下发动画效果，针对播放次数的幸运弹窗，只有观看本轮激励广告后才能进入下一阶段
      //譬如第一次激励广告广告商未返回，无论触发几次幸运弹窗都是第一轮，第四轮时也发放第三轮奖励次数，只有第四个激励广告用户观看完成后才能下发当日无限次数观看，每日凌晨五点触发重置。
    },
    "adList": [
      {
        "adType": 1,     //类型1是开屏广告，类型2是激励广告  广告使用Google中介器接入 详情见官方接入文档：https://developers.google.com/admob/android/mediation?hl=zh-cn
        "advertiser": "google",
        "config": {
          "appId": "string",   //appid
          "adUnitId": "string"  //广告单元id
        }
      }
    ],
    "recommend": [   //搜索页推荐网站
      {
        "pictureUrl": "string",
        "name": "string",
        "url": "string"
      }
    ],
    "lcList": {   //推荐列表
      "us": ["https://example.com/short-link"]
    }
  }
}
```

主要字段：

| 字段 | 类型 | 说明 |
|---|---|---|
| `NB01` | `bool` | 是否隐藏会员入口,为true时点击购买订阅弹窗服务繁忙，false时可以正常购买 |   
| `ios.iosVerifyShareKey` | `string` | iOS 收据验证共享密钥 |
| `ios.sandBoxTest` | `bool` | 是否使用 iOS 沙盒验证 |
| `quotaConfig.*` | `number` | 观看、广告奖励等额度配置， |
| `adList` | `array` | 广告配置列表 |
| `adList[].adType` | `int` | `1` 开屏广告，`5` 激励广告 |
| `adList[].advertiser` | `string` | 广告平台 |
| `adList[].config.appId` | `string` | 广告 App ID |
| `adList[].config.adUnitId` | `string` | 广告位 ID |
| `recommend` | `array` | 推荐网站配置 |
| `recommend[].pictureUrl` | `string` | 推荐图片 |
| `recommend[].name` | `string` | 推荐名称 |
| `recommend[].url` | `string` | 推荐链接 |
| `lcList.us` | `array<string>` | 落地页或推荐链接列表 |


## 4.2 游客登录

```http
POST /app-api/member/auth/app_tourist_login
Content-Type: application/json
```

### 请求体

```json
{
  "deviceCode": "device-uuid",  //使用uuid库生成
  "source": "com.smartplay.iaptest.devA",   //对应包的Bundle id
  "uniqueId": "203.0.113.10"   //获取公网ip  GET https://ipv4.icanhazip.com    GET https://api.ipify.org/
}
```

| 参数 | 类型 | 必填 | 说明 |
|---|---|---:|---|
| `deviceCode` | `string` | 是 | 设备标识 |
| `source` | `string` | 是 | 当前平台的游客来源标识 |
| `uniqueId` | `string` | 是 | 公网 IP 或其他唯一标识，失败时可为空 |

### 响应

```json
{
  "code": 0,
  "msg": "success",
  "data": {
    "accessToken": "token-value",   
    "userId": "visitor-001",
    "domainId": "domain-001",
    "shortLink": "short-link-value"
  }
}
```

| 字段 | 类型 | 说明 |
|---|---|---|
| `accessToken` | `string` | 后续请求的 Bearer Token |
| `userId` | `string` | 游客用户 ID |
| `domainId` | `string` | 用户所属域 |
| `shortLink` | `string` | 用户关联短链 |

## 4.3 批量获取落地页信息

```http
POST /app-api/flow/land-page/info_by_links_list
Content-Type: application/json
```

请求体为数组：

```json
[
  {
    "externalLinks": "link-001",  //包配置lcList.us返回的短链
    "packageName": "com.smartplay.iaptest.devA"  // 对应包的Bundle id
  },
  {
    "externalLinks": "link-002",
    "packageName": "com.smartplay.iaptest.devA"
  }
]
```

| 参数 | 类型 | 说明 |
|---|---|---|
| `externalLinks` | `string` | 外部链接或短链标识，客户端会过滤空值 |
| `packageName` | `string` | 当前平台的 `touristSource` |

响应示例：

```json
{
  "code": 0,
  "msg": "success",
  "data": [
    {
      "shortCover": "https://example.com/cover.jpg",    //推荐列表的channel的封面图
      "netDiskInfo": {
        "landingPage": "landing-page-001",
        "name": "视频名称",
        "isFolder": false,
        "coverImage": "https://example.com/cover.jpg",
        "length": 120,
        "fileSize": 104857600,
        "fileUrl": "https://cdn.example.com/video.mp4",
        "originUrl": "https://cdn.example.com/origin.mp4"
      },
      "extraInfo": {
        "channelName": "频道名称",    //推荐列表的channel名称
        "externalLinks": "link-001",     //推荐列表的channel的短链
        "videoFileCount": 10     //推荐列表的channel内的视频数
      }
    }
  ]
}
```

## 4.4 获取单个落地页或频道详情

```http
GET /app-api/flow/land-page/info_by_links
```

### Query 参数

| 参数 | 类型 | 必填 | 说明 |
|---|---|---:|---|
| `externalLinks` | `string` | 是 | 短链或落地页标识 |
| `password` | `string` | 是 | 访问密码，公开内容传空字符串 |
| `packageName` | `string` | 是 | 当前平台的 `touristSource` |

示例：

```http
GET /app-api/flow/land-page/info_by_links?externalLinks=abc123&password=&packageName=com.smartplay.iaptest.devA
```

当前客户端实际读取：

```json
{
  "code": 0,
  "msg": "success",
  "data": {
    "extraInfo": {
      "channelName": "频道名称",
      "externalLinks": "abc123"
    }
  }
}
```

客户端要求以下字段有效：

```text
data.extraInfo.channelName
data.extraInfo.externalLinks
```

服务端也可以返回 `shortCover`、`folderName`、`netDiskInfo`、`advertisementInfo` 等扩展字段。

## 4.5 获取频道内容分页

```http
GET /app-api/flow/land-page/list_by_links_page
```

### Query 参数

| 参数 | 类型 | 必填 | 默认值/范围 | 说明 |
|---|---|---:|---|---|
| `externalLinks` | `string` | 是 | 非空 | 频道或落地页标识 |
| `pageNo` | `int` | 是 | 默认 `1` | 小于 1 时修正为 1 |
| `pageSize` | `int` | 是 | 默认 `10`，范围 `1..50` | 每页数量 |
| `packageName` | `string` | 是 | 当前平台 `Bundle id` | App 来源标识 |

### 响应

```json
{
  "code": 0,
  "msg": "success",
  "data": {
    "list": [
      {
        "id": "video-001",
        "landingPage": "landing-page-001",   //返回文件夹或视频的短链
        "name": "视频名称",    //名称
        "coverImage": "https://example.com/cover.jpg",  //如果是文件夹则使用文件夹icon，如果是视频则使用此封面图

        "m3u8Url": "https://cdn.example.com/video.m3u8",   //视频播放地址
        "length": 120,
        "fileSize": 104857600,
        "isFolder": false,    //判断是文件夹还是视频
        "createTime": 1710000000000,
        "childrenFileNum": 0    //文件夹下文件数量
      }
    ],
    "total": 100
  }
}
```

| 字段 | 类型 | 说明 |
|---|---|---|
| `data.list` | `array` | 当前页数据 |
| `data.total` | `int` | 总数量 |
| `list[].id` | `string` | 内容 ID |
| `list[].landingPage` | `string` | 落地页标识 |
| `list[].name` | `string` | 内容名称，空名称会被过滤 |
| `list[].coverImage` | `string` | 封面地址 |
| `list[].m3u8Url` | `string` | HLS 播放地址 |
| `list[].length` | `number` | 视频时长 |
| `list[].fileSize` | `number` | 文件大小 |
| `list[].isFolder` | `bool` | 是否文件夹 |
| `list[].createTime` | `number` | Unix 时间戳，客户端按毫秒转换 |
| `list[].childrenFileNum` | `number` | 子文件数量，可在 `extraInfo` 中提供 |

## 4.6 推荐/搜索视频 search-check

```http
GET /app-api/flow/search-check
```

### Query 参数

| 参数 | 类型 | 必填 | 说明 |
|---|---|---:|---|
| `userId` | `string` | 是 | 当前游客用户 ID 登录接口返回|
| `feedId` | `string` | 否 | 后续分页使用上次返回值 |
| `cursor` | `string` | 否 | 后续分页使用上次返回值 |
| `pageSize` | `int` | 否 | 默认 `10`，范围 `1..20` |
| `query` | `string` | 否 | 搜索关键词或筛选词 |
| `packageName` | `string` | 是 | 当前平台的 `touristSource` |

### 响应

```json
{
  "code": 0,
  "msg": "success",
  "data": {
    "feedId": "feed-001",
    "nextCursor": "cursor-002",
    "hasMore": true,
    "list": [
      {
        "videoId": "video-001",
        "shortLink": "short-link-001",
        "m3u8Url": "https://cdn.example.com/video.m3u8",
        "videoName": "视频名称",
        "coverUrl": "https://cdn.example.com/cover.jpg"
      }
    ]
  }
}
```

| 字段 | 类型 | 说明 |
|---|---|---|
| `feedId` | `string` | Feed 标识 |
| `nextCursor` | `string` | 下一页游标 |
| `hasMore` | `bool` | 是否还有更多 |
| `list` | `array` | 视频列表 |
| `list[].videoId` | `string` | 视频 ID，播放场景要求存在 |
| `list[].shortLink` | `string` | 视频短链，可选 |
| `list[].m3u8Url` | `string` | HLS 播放地址，播放场景要求存在 |
| `list[].videoName` | `string` | 视频名称 |
| `list[].coverUrl` | `string` | 封面地址，可选 |

分页流程：

1. 首次请求不传 `feedId` 和 `cursor`；
2. 保存响应中的 `feedId` 和 `nextCursor`；
3. 下一次请求传入上一次的 `feedId` 和 `nextCursor`；
4. `hasMore == false` 时停止请求。

## 4.7 创建 iOS 权益订单

```http
POST /app-api/flow/rights-order/buy
Content-Type: application/json
```

### 请求体

```json
{
  "rightsName": "test.plan.month",
  "price": "9.99",  //真实价格
  "usdPrice": "999",  //999或9999
  "packageName": "com.smartplay.iaptest.dev",
  "versionCode": "1.0.0",
  "payType": "1",   //1为ios 
  "source": "ios"
}
```

| 参数 | 类型 | 说明 |
|---|---|---|
| `rightsName` | `string` | iOS 商品 ID |
| `price` | `string` | App Store 本地价格 |
| `usdPrice` | `string` | 美元价格或方案价格 |
| `packageName` | `string` | `touristSource.ios` |
| `versionCode` | `string` | App 版本 |
| `payType` | `string` | 固定为 `"1"` |
| `source` | `string` | 固定为 `"ios"` |

### 响应

```json
{
  "code": 0,
  "msg": "success",
  "data": "order-id-001"
}
```

`data` 是订单号，客户端会将其转换成字符串保存。

## 4.8 Android/Google 购买确认

```http
POST /app-api/flow/rights-order/google/buy
Content-Type: application/json
```

### 请求体

```json
{
  "rightsName": "pp.plan.month",
  "price": "9.99",    //真实返回的价格
  "usdPrice": "999",  //999或9999
  "packageName": "com.smartplay.iaptest.devA",
  "versionCode": "1.0.0",
  "payType": "2",   
  "source": "android",
  "all": "{\"productId\":\"pp.plan.month\",\"purchaseToken\":\"token\"}"
}
```

| 参数 | 类型 | 说明 |
|---|---|---|
| `rightsName` | `string` | Google 商品 ID |
| `price` | `string` | Google Play 本地价格 |
| `usdPrice` | `string` | 美元价格 |
| `packageName` | `string` | `touristSource.android` |
| `versionCode` | `string` | App 版本 |
| `payType` | `string` | 固定为 `"2"` |
| `source` | `string` | 固定为 `"android"` |
| `all` | `string` | Google 购买凭据 JSON 字符串 |

### 响应

客户端只检查 `code == 0`，当前不读取 `data`：

```json
{
  "code": 0,
  "msg": "success",
  "data": null
}
```

## 4.9 iOS 购买结果确认

```http
POST /app-api/flow/rights-order/buySuccess
Content-Type: application/json
```

### 请求体

```json
{
  "verificationData": "app-store-verification-data",
  "purchaseID": "order-id-001",
  "status": "purchased",
  "sandBoxTest": false,
  "transactionId": "transaction-id-001",
  "iosVerifyShareKey": "shared-secret"
}
```

| 参数 | 类型 | 说明 |
|---|---|---|
| `verificationData` | `string` | App Store 收据验证数据 |
| `purchaseID` | `string` | 创建订单接口返回的订单号 |
| `status` | `string` | `purchased`、`canceled` 或 `error` |
| `sandBoxTest` | `bool` | 是否使用沙盒环境 |
| `transactionId` | `string` | StoreKit 交易号 |
| `iosVerifyShareKey` | `string` | 发布配置接口下发的共享密钥 |

`restored` 状态会转换为 `purchased`；`pending` 状态不会发送请求。

### 响应

客户端只判断 `code == 0`：

```json
{
  "code": 0,
  "msg": "success",
  "data": null
}
```

## 4.10 查询用户权益

```http
GET /app-api/member/user/get
```

无 Query 参数、无请求体，需要携带游客 Token。

### 响应

```json
{
  "code": 0,
  "msg": "success",
  "data": {
    "adStatus": "normal",
    "rightExpireTime": 1710000000000
  }
}
```

| 字段 | 类型 | 说明 |
|---|---|---|
| `adStatus` | `string` / `number` | 广告或会员状态 |
| `rightExpireTime` | `number` / `string` | 权益到期时间 |

`rightExpireTime` 兼容：

- Unix 秒级时间戳；
- Unix 毫秒级时间戳；
- 可解析的日期字符串。

客户端通过到期时间是否晚于当前时间判断权益是否有效。

# 5. 辅助请求和媒体请求

## 5.1 公网 IP 探测

游客首次登录前可能请求：

```http
GET https://ipv4.icanhazip.com
GET https://api.ipify.org/
```

返回纯文本 IP，用作登录接口的 `uniqueId`。这不是业务 API，三方通常不需要封装到业务接口模块中。

## 5.2 视频/CDN 请求

接口返回的以下字段是动态资源 URL：

```text
m3u8Url
fileUrl
originUrl
coverUrl
coverImage
```

这些地址不应拼接到 `apiBaseUrl` 下，也不使用统一的 `{code,msg,data}` 响应结构。播放器可能使用 HLS、Range 请求和专用 User-Agent。

# 6. 错误处理

## 6.1 HTTP 错误

| 情况 | 处理建议 |
|---|---|
| `401` | 重新游客登录并重试一次 |
| `4xx` | 检查参数、权限和 Token |
| `5xx` | 服务端异常，可按策略重试 |
| 超时 | 默认 15 秒，建议提示用户或重试 |
| 非 JSON | 按响应格式错误处理 |
| 网络不可用 | 提示网络异常 |


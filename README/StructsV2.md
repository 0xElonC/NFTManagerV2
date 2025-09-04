0# ----- 订单与撮合细节 -----
## Order (卖家或买家挂的订单集合)

| Field            | Type      | 说明                                 |
| ---------------- | --------- | ---------------------------------- |
| trader           | address   | 挂单方地址（卖家或买家）。                      |
| collection       | address   | NFT 合约地址。                          |
| listingsRoot     | bytes32   | 多个 `Listing` 的 Merkle 树根，用于批量订单压缩。 |
| numberOfListings | uint256   | 挂单中包含的 listing 总数。                 |
| expirationTime   | uint256   | 订单过期时间（时间戳）。                       |
| assetType        | AssetType | 资产类型（ERC721 或 ERC1155）。            |
| makerFee         | FeeRate   | 挂单方需支付的手续费。                        |
| salt             | uint256   | 随机数，避免重放攻击。                        |


## Listing (卖家提供的某个NFT的卖单)
| Field   | Type    | 说明                   |
| ------- | ------- | -------------------- |
| index   | uint256 | 该 `Listing` 在订单中的序号。 |
| tokenId | uint256 | NFT 的 tokenId。       |
| amount  | uint256 | 出售数量（ERC721 永远是 1）。  |
| price   | uint256 | 单个 NFT 的价格。          |

## Taker (买家需求)
| Field   | Type    | 说明                   |
| ------- | ------- | -------------------- |
| tokenId | uint256 | 买方想要购买的 NFT tokenId。 |
| amount  | uint256 | 买方想要购买的数量。           |


## Exchange(撮合选中的Listing + Taker)
| Field   | Type       | 说明                                                |
| ------- | ---------- | ------------------------------------------------- |
| index   | uint256    | `listing` 在订单的 Merkle 树中的索引。                      |
| proof   | bytes32\[] | 用来验证 `listing` 存在于订单的 `listingsRoot` 的 Merkle 证明。 |
| listing | Listing    | 卖方提供的具体挂单信息。                                      |
| taker   | Taker      | 买方请求的成交信息。                                        |


# ----- 撮合入口 -----

## TakeAsk (用来撮合的卖单数据，买家请求的集合)
| Field          | Type        | 说明                              |
| -------------- | ----------- | ------------------------------- |
| orders         | Order\[]    | 卖方订单集合（挂单方的基础信息）。               |
| exchanges      | Exchange\[] | 撮合时买方提供的具体购买请求，与 `orders` 一一对应。 |
| takerFee       | FeeRate     | 买家支付的手续费比例及收款地址。                |
| signatures     | bytes       | 卖家订单的批量签名（EIP712）。              |
| tokenRecipient | address     | 接收 NFT 的地址（通常是买家自己）。            |

## TaskAskSigle(单个买家的请求)
| Field          | Type     | 说明         |
| -------------- | -------- | ---------- |
| order          | Order    | 卖方集合订单。    |
| exchange       | Exchange | 单次撮合的交易请求。 |
| takerFee       | FeeRate  | 买家支付的手续费。  |
| signature      | bytes    | 卖方订单的签名。   |
| tokenRecipient | address  | NFT 接收人。   |

## TakeBid (撮合买单数据，卖家请求的集合)
| Field      | Type        | 说明         |
| ---------- | ----------- | ---------- |
| orders     | Order\[]    | 买方挂单集合。    |
| exchanges  | Exchange\[] | 卖方提供的成交请求。 |
| takerFee   | FeeRate     | 卖家支付的手续费。  |
| signatures | bytes       | 买方订单的签名集合。 |

## TakeBidsingle (撮合单个卖家的请求)
| Field     | Type     | 说明        |
| --------- | -------- | --------- |
| order     | Order    | 单个买方订单。   |
| exchange  | Exchange | 单次撮合请求。   |
| takerFee  | FeeRate  | 卖家支付的手续费。 |
| signature | bytes    | 买方订单的签名。  |

# ---- 交易执行与状态更新（链上记录了订单的消耗情况） -----

## Transfer (描述一次NFT转账动作)
| Field      | Type      | 说明                   |
| ---------- | --------- | -------------------- |
| trader     | address   | 转账发起方地址。             |
| collection | address   | NFT 合约地址。            |
| id         | uint256   | NFT 的 tokenId。       |
| amount     | uint256   | 数量（ERC721 = 1）。      |
| assetType  | AssetType | NFT 类型（ERC721/1155）。 |

## FungibleTransfer （处理资金结算（ETH/ERC20））
| Field               | Type               | 说明              |
| ------------------- | ------------------ | --------------- |
| totalProtocolFee    | uint256            | 本次撮合累计的协议手续费总额。 |
| totalSellerTransfer | uint256            | 卖家累计应得金额。       |
| totalTakerFee       | uint256            | 买家支付的手续费总额。     |
| feeRecipientId      | uint256            | 当前手续费接收方 ID。    |
| makerId             | uint256            | 当前挂单方 ID。       |
| feeRecipients       | address\[]         | 所有手续费接收人地址。     |
| makers              | address\[]         | 所有挂单方地址。        |
| makerTransfers      | uint256\[]         | 每个挂单方应得的金额。     |
| feeTransfers        | uint256\[]         | 每个手续费接收人的金额。    |
| executions          | AtomicExecution\[] | 每次成交的资金分配记录。    |

## AtomicExecution (描述一次完整的资金结算)
| Field               | Type        | 说明            |
| ------------------- | ----------- | ------------- |
| makerId             | uint256     | 挂单方 ID（索引）。   |
| sellerAmount        | uint256     | 卖家应得金额。       |
| makerFeeRecipientId | uint256     | 挂单方手续费接收人 ID。 |
| makerFeeAmount      | uint256     | 挂单方支付的手续费金额。  |
| takerFeeAmount      | uint256     | 买方支付的手续费金额。   |
| protocolFeeAmount   | uint256     | 协议手续费金额。      |
| stateUpdate         | StateUpdate | 成交后订单状态更新。    |

## StateUpdate (更新状态，订单撮合后链上的状态变化)
| Field     | Type    | 说明               |
| --------- | ------- | ---------------- |
| trader    | address | 挂单方地址。           |
| hash      | bytes32 | 订单哈希。            |
| index     | uint256 | 订单内的 listing 索引。 |
| value     | uint256 | 本次撮合成交的数量。       |
| maxAmount | uint256 | 订单允许的最大成交数量。     |

# ----- 手续费相关 -----

## Fees (手续费率汇总，包含平台协议手续费率和买方或者卖方的额外手续费率)
| Field       | Type    | 说明              |
| ----------- | ------- | --------------- |
| protocolFee | FeeRate | 协议收取的手续费率。      |
| takerFee    | FeeRate | 买方或卖方额外支付的手续费率。 |

## FeeRate (手续费率)
| Field     | Type    | 说明             |
| --------- | ------- | -------------- |
| recipient | address | 手续费接收地址。       |
| rate      | uint16  | 手续费比例（一般用万分比）。 |

## Cancel （用来取消订单）
| Field  | Type    | 说明              |
| ------ | ------- | --------------- |
| hash   | bytes32 | 订单哈希。           |
| index  | uint256 | 取消的 listing 索引。 |
| amount | uint256 | 取消数量。           |

### ExcutionBatch (执行批次)
| Field  | Type    | 说明              |
| ------ | ------- | --------------- |
| taker   | address | 发起者地址           |
| oderType  | OderType | 订单类型 |
| transfers | Transfer[] | 交易      |
| length | uint256 | 批次长度      |
这个结构体在合约内会直接使用calldata 内手动化存入数据


![alt text](image.png)
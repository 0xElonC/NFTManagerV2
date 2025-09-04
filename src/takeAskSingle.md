
### 卖家挂单买家购买

1、调用takeAskSingle() 
    传入 TaskAskSingle 、 oracleSignature
    TaskAskSingle: 单个买单请求
    再调用内部 _takeAskSingle
    里面包含：
    （1）卖方指定NFT的一个系列卖单 orders
    （2）根据买单撮合的请求 exchange
    （3）发起者买家所需要的收费 takerFee
    （4）卖方对指定NFT的签名 sighature
    （5）NFT的接受人tokenRecipient
    oracleSignature：oracle签名

2、验证订单和挂单 _validateOrderAndListing()
    传入数据:order(卖家单个NFT挂单集合)、
            ordertype(订单类型)、
            exchange(撮合订单信息)、
            signature(卖家签名)、
            fees(买家手续费)
    验证分为两个部分
    （1） 验证卖家订单是否有效：
        *得到订单哈希
        *通过传入的signature验证签名(_verifyAuthorization)：
            把订单哈希生成 签名消息
            解析出signature 得到 v r s 
            通过_verify 得到地址对比是否相同
    （2） 验证撮合订单是否有效
        *通过 Order 中存储的 挂单信息merkle树根 + exchange中保存的listing的验证路径+ listing订单的哈希，验证撮合订单中的listing是有效的
        *判断撮合订单的NFT数量或者ID是否有效

3、验证信息没问题，开始创建交易执行批次 _initializeSingleExecution
    传入： :order(卖家单个NFT挂单集合)、
            ordertype(订单类型)、
            listing.tokenId(撮合订单信息中挂单的tokenId)、
            listing.amount(撮合订单信息中挂单的tokenId的NFT的数量)、
            NFT的接受人tokenRecipient(买家地址)

    （2）构建完交易执行信息 executionLength ，
        *存入其他信息后，通过_insertNonfungibleTransfer写入transfer[]数组
4、通过_executeNonfungibleTransfers 先转NFT




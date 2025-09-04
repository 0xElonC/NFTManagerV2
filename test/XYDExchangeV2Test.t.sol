// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/XYDExchangeV2.sol";
import "../src/interfaces/IXYDExchangeV2.sol"; // 接口
import "../src/Executor.sol";
import "../src/Delegate.sol";
import "../src/utils/Validation.sol";
import "../src/utils/Signatures.sol";
import "../src/NFT/TestERC721.sol";
import {
    TakeAsk,
    TakeBid,
    TakeAskSingle,
    TakeBidSingle,
    Order,
    Exchange,
    Fees,
    FeeRate,
    AssetType,
    OrderType,
    Transfer,
    FungibleTransfers,
    StateUpdate,
    AtomicExecution,
    Cancel,
    Listing
} from "../src/struct/Structs.sol";
import "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { MerkleProof } from "lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/utils/cryptography/MerkleProof.sol";

contract XYDExchangeV2Test is Test{
    //核心合约
    XYDExchangeV2 public xydExchangeV2;//逻辑合约
    ERC1967Proxy public exchangeProxy;//proxy合约实例
    IXYDExchangeV2 public exchange; // 代理合约的接口实例（用于调用功能）
    Delegate public delegate;
    TestERC721 public nft;
    //测试账户
    uint256 public sellerPK = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    uint256 public buyerPK = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
    address public seller;
    address public buyer;
    address public owner;
    // ========== 测试常量 ==========
    address public TEST_COLLECTION; // 测试用 ERC721/1155 地址
    uint256 public constant TEST_TOKEN_ID = 1; // 测试 Token ID
    uint256 public constant TEST_AMOUNT = 1; // ERC1155 数量（ERC721 固定为 1）
    uint256 public constant TEST_PRICE = 1 ether; // 订单价格（1 ETH）
    uint256 public EXPIRATION_TIME = block.timestamp + 1 hours; // 订单过期时间（1小时后）
    uint256 public constant SALT = 0x12345678; // 订单随机盐值（防重放）

    // ========== 测试结构体实例 ==========
    TakeAskSingle public testTakeAskSingle; // 待测试的 TakeAskSingle 结构体
    bytes public testSignature; // 卖家对订单的签名
    using MerkleProof for bytes32[];
    function setUp() public{
        seller = vm.addr(sellerPK);
        buyer  = vm.addr(buyerPK);
        owner  = address(this);
        console.log(seller);
        vm.startPrank(owner);
        delegate = new Delegate(owner);
        xydExchangeV2 = new XYDExchangeV2();
        console.log(unicode"实现合约 XYDManagerV2 部署地址:", address(xydExchangeV2));

        bytes memory initData = abi.encodeCall(
            IXYDExchangeV2.initialize,
            (owner,address(delegate),address(0))
        );

        exchangeProxy = new ERC1967Proxy(address(xydExchangeV2),initData);// 先不给 initData，等会手动初始化
        console.log(unicode"代理合约 Proxy 部署地址:", address(exchangeProxy));

        exchange = IXYDExchangeV2(address(exchangeProxy));
        exchange.setGovernor(owner);
        delegate.approveContract(address(exchangeProxy));
        // 验证关联是否正确
        assertEq(exchange.getDelegate(), address(delegate));
        //部署测试NFT
        nft = new TestERC721("TestNFT","TNT",owner);
        TEST_COLLECTION = address(nft);
        nft.mint(seller);
        vm.startPrank(seller);
        nft.setApprovalForAll(address(delegate),true);

        //初始化TaskAskSingle所需的结构体
        Listing memory testListing = _createTestListing();
        Order memory testOrder = _createTestOrder(testListing);
        Exchange memory testExchange = _createTestExchange(); // 生成测试 Exchange
        FeeRate memory testTakerFee = _createTestFeeRate(); // 生成测试手续费

        // 生成卖家对订单的签名（关键：模拟真实签名流程）
        testSignature = _signOrder(testOrder, sellerPK);

        //组装TakeAskSingle 结构体
        testTakeAskSingle = TakeAskSingle({
            order:testOrder,
            exchange:testExchange,
            takerFee:testTakerFee,
            signature:testSignature,
            tokenRecipient:buyer
        });

        vm.deal(buyer,2 ether);
    }
    /// @notice 测试 部署初始化 是否成功
    function test_Deployment_Initialization() public {
        // 验证 governor 变量（如果已设置）
        assertEq(exchange.getGovernor(), owner, unicode"Governor 初始化错误");
    }

    //-------------------------------辅助函数--------------------------
    function _createTestListing() internal view returns(Listing memory){
        return Listing({
            index:0,
            tokenId:1,
            amount:1,
            price:1000000000000000000 wei
        });
    }
    /**
     * @dev 生成测试 Order 结构体
     */
    function _createTestOrder(Listing memory listing) internal view returns (Order memory) {
        bytes32 listinghash = keccak256(abi.encode(
            listing.index,
            listing.tokenId,
            listing.amount,
            listing.price
        ));
        return Order({
            trader: seller, // 订单卖家（签名者）
            collection: TEST_COLLECTION, // 测试藏品地址
            listingsRoot: listinghash,
            numberOfListings: 1, // 订单包含 1 个 listing
            expirationTime: EXPIRATION_TIME, // 24小时后过期
            assetType: AssetType.ERC721, // 测试 ERC721 类型
            makerFee: FeeRate({recipient: 0x1000000000000000000000000000000000000000, rate: 50}), // 卖家手续费：50bps（0.5%）
            salt: SALT // 随机盐值
        });
    }
    /**
     * @dev 生成测试 FeeRate 结构体（买家手续费）
     */
    function _createTestFeeRate() internal pure returns (FeeRate memory) {
        return FeeRate({
            recipient: 0x1000000000000000000000000000000000000000, // 手续费接收地址（测试用）
            rate: 100 // 100bps（1%）手续费率
        });
    }
    /**
     * @dev 生成测试 Exchange 结构体
     */
    function _createTestExchange() internal pure returns (Exchange memory) {
        return Exchange({
            index: 0, // listing 在订单中的索引（第 0 个）
            proof: new bytes32[](0), // 简化测试：默认为空 Merkle 证明（真实场景需生成）
            listing: Listing({
                index: 0,
                tokenId: TEST_TOKEN_ID, // 测试 Token ID
                amount: TEST_AMOUNT, // ERC721 数量为 1
                price: TEST_PRICE // 订单价格 1 ETH
            }),
            taker: Taker({
                tokenId: TEST_TOKEN_ID, // 买家要购买的 Token ID
                amount: TEST_AMOUNT // 购买数量
            })
        });
    }
    /**
     * @dev 对 Order 进行签名（模拟卖家签名）
     * @param order 待签名的订单
     * @param privateKey 卖家私钥
     * @return 签名结果（bytes）
     */
    function _signOrder(Order memory order, uint256 privateKey) internal view returns (bytes memory) {

        bytes32 orderType = exchange.getOrderType();
        console.logBytes32(orderType);
        // 1. 将 Order 编码为哈希（需与合约中签名验证的编码逻辑完全一致！）
        bytes32 orderHash = keccak256(abi.encode(
            orderType,
            order.trader,
            order.collection,
            order.listingsRoot,
            order.numberOfListings,
            order.expirationTime,
            order.assetType,
            _hashFeeRate(order.makerFee),
            order.salt,
            OrderType.ASK,
            0
        ));

        console.log("----orderHash-----");
        console.logBytes32(orderHash);

        // 2. 用 ECDSA 签名（若合约用了 EIP-712，需替换为 EIP-712 签名逻辑）
        (uint8 v, bytes32 r, bytes32 s) =_hashToSign(privateKey, orderHash);
        return abi.encodePacked(r, s, v); // 组装签名（r + s + v 格式）
    }

    function test_takeAskSingle_Success() public {
    // 1. 模拟买家调用 takeAskSingle（需先授权 NFT？若需要）
    vm.startPrank(buyer); 
    uint256 beforeBuyerEth = buyer.balance; // 记录买家调用前 ETH 余额
    console.log(beforeBuyerEth);

    // 2. 调用 takeAskSingle（需传入 ETH 支付订单价格）
    exchange.takeAskSingle{value: 2 ether}(testTakeAskSingle); // 传 2 ETH 支付

    // 3. 验证结果（根据合约逻辑调整断言）
    // 3.1 验证买家 ETH 减少（价格 + 手续费）
    uint256 takerFeeAmount = (TEST_PRICE * testTakeAskSingle.takerFee.rate) / 10000; // 1% 手续费
    uint256 makerFeeAmount = (TEST_PRICE * testTakeAskSingle.order.makerFee.rate) / 10000; // 0.5% 卖家手续费
    uint256 expectedEthSpent = TEST_PRICE + takerFeeAmount+makerFeeAmount;
    assertEq(beforeBuyerEth - buyer.balance, expectedEthSpent, unicode"买家 ETH 消耗错误");

    // 3.2 验证卖家收到订单金额
    uint256 expectedSellerReceive = TEST_PRICE;
    assertEq(seller.balance, expectedSellerReceive, unicode"卖家未收到订单金额");

    // 3.3 验证手续费接收地址收到手续费
    address feeRecipient = testTakeAskSingle.takerFee.recipient;
    assertEq(feeRecipient.balance, takerFeeAmount + makerFeeAmount, unicode"手续费接收错误");

    // 3.4 验证买家收到 NFT（需调用藏品合约的 ownerOf 函数）
    // 假设 TEST_COLLECTION 是 ERC721 合约，需导入 ERC721 接口
    // ERC721(TEST_COLLECTION).ownerOf(TEST_TOKEN_ID) == buyer;
    // 若测试环境中藏品合约未部署，可忽略此步或用 Mock 合约
}
    function _hashFeeRate(
        FeeRate memory feeRate
    )public view returns(bytes32){
        bytes32 _FEE_TYPEHASH = exchange.getFeeType();
        return keccak256(
            abi.encode(
                _FEE_TYPEHASH,
                feeRate.recipient,
                feeRate.rate
            )
        );
    }
    /**
     * 获取EIP712签名信息
     * @param orderhash 订单哈希
     */
    function _hashToSign(
        uint256 pk,
        bytes32 orderhash
    )internal view returns(uint8 v, bytes32 r, bytes32 s){
        bytes32 _DOMAIN_SEPARATOR = exchange.getDomainSeparator();
        console.log("_DOMAIN_SEPARATOR");
        console.logBytes32(_DOMAIN_SEPARATOR);
        bytes32 signatures =  keccak256(
            bytes.concat(
                bytes2(0x1901),
                _DOMAIN_SEPARATOR,
                orderhash)
        );
        console.log("signatures");
        console.logBytes32(signatures);
        ( v,  r,  s) = vm.sign(pk, signatures);
    }
}
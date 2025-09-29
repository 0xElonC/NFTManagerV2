// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
import {Ownable2StepUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";
import {UUPSUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import "./Executor.sol";
import "./interfaces/IXYDExchangeV2.sol";
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
} from "./struct/Structs.sol";

contract XYDExchangeV2 is
    IXYDExchangeV2,
    Ownable2StepUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    Executor
{
    
    address public governor;
    //防止部署时被初始化
    function _authorizeUpgrade(address) internal override onlyOwner {}

    constructor()Executor() {
        _disableInitializers();
    }

    function initialize(
        address ownerAddress,
        address delegateAddress,
        address pool
    ) external initializer {
        __UUPSUpgradeable_init();
        __Ownable_init(ownerAddress);
        __ReentrancyGuard_init();
        verifyDomain();

        _DELEGATE = delegateAddress;
        _POOL = pool;
        (_DOMAIN_SEPARATOR,_ORDER_TYPEHASH,_FEE_TYPEHASH) = _createTypeHash(address(this));
    }

    modifier onlyGovernor(){
        require(msg.sender != governor,"no governor");
        _;
    }

    /**
     * 设置管理者
     * @param _governor 管理者地址
     */
    function setGovernor(
        address _governor
    )external onlyOwner{
        governor = _governor;
        emit SetGovernor(governor);
    }

    function getGovernor()external returns(address){
        return governor;
    }
    function getDelegate() external view returns (address){
        return _DELEGATE;
    }
    function setDelegate(
        address delegate
    ) external onlyOwner{
        _DELEGATE = delegate;
        emit SetDelegate(_DELEGATE);
    }
    function getPool() external view returns (address){
        return _POOL;
    }
    function setPool(
        address pool
    ) external onlyOwner{
        _POOL = pool;
        emit SetPool(_POOL);
    }
    /*//////////////////////////////////////////////////////////////
                          Test
    //////////////////////////////////////////////////////////////*/
    function getOrderType()external view returns(bytes32){
        return _ORDER_TYPEHASH;
    }
    function getFeeType()external view returns(bytes32){
        return _FEE_TYPEHASH;
    }
    function getDomainSeparator()external view returns(bytes32){
        return _DOMAIN_SEPARATOR;
    }
    /*//////////////////////////////////////////////////////////////
                          EXECUTION WRAPPERS
    //////////////////////////////////////////////////////////////*/
    /**
     * 单个购买NFT 公共接口
     * @param inputs 单个买单请求订单
     */
    function takeAskSingle(
        TakeAskSingle memory inputs
        //bytes calldata oracleSignature
    )
        external
        payable
        nonReentrant
        //verifyOracleSignature(_hashCalldata(msg.sender), oracleSignature)
        {
            _takeAskSingle(
                inputs.order,
                inputs.exchange,
                inputs.takerFee,
                inputs.signature,
                inputs.tokenRecipient
            );
        }

    function takeBidSingle(
        TakeBidSingle memory inputs
    )
        external
        payable
        nonReentrant{
            _takeBidSingle(
                inputs.order,
                inputs.exchange,
                inputs.takerFee,
                inputs.signature
            );
        }

    /*//////////////////////////////////////////////////////////////
                        EXECUTION FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * 单个购买订单
     * @param order 挂单集合
     * @param exchange 撮合订单体
     * @param takerFee 发起者手续费
     * @param signature 挂单签名
     * @param tokenRecipient NFT接收地址
     */
    function _takeAskSingle(
        Order memory order,
        Exchange memory exchange,
        FeeRate memory takerFee,
        bytes memory signature,
        address tokenRecipient
    ) internal{
        Fees memory fees = Fees(protocolFee,takerFee);
        Listing memory listing = exchange.listing;
        uint256 takerAmount = exchange.taker.amount;
        //验证订单和挂单
        if(!_validateOrderAndListing(order, OrderType.ASK, exchange, signature, fees)){
            revert InvalidOrder();
        }
        //创建单个交易执行批次
        bytes memory executionBatch = _initializeSingleExecution(
            order,
            OrderType.ASK,
            listing.tokenId,
            listing.amount,
            tokenRecipient
        );
        //修改状态
        unchecked{
            amountTaken[order.trader][bytes32(order.salt)][listing.index] += takerAmount;
        }

        //独立作用域，完成后释放内存
        {
            bool[] memory successfulTransfers = _executeNonfungibleTransfers(executionBatch,1);
            if(!successfulTransfers[0]){
                revert TokenTransferFailded();
            }
        }
        (
            uint256 totalPrice,
            uint256 protocalFeeAmount,
            uint256 makerFeeAmount,
            uint256 takerFeeAmount
        ) = _computeFees(listing.price,takerAmount,order.makerFee,fees);
        //检查余额是否足够 交易总金额+吃单者的手续费
        unchecked {
            if(address(this).balance < totalPrice + takerFeeAmount){
                revert InsufficientFunds();
            }
        }

        //执行交易
        _transferETH(fees.protocolFee.recipient,protocalFeeAmount);
        _transferETH(order.makerFee.recipient,makerFeeAmount);
        _transferETH(fees.takerFee.recipient,takerFeeAmount);
        
        unchecked {
            _transferETH(order.trader,totalPrice);
        }
        //_emitExecutionSingleAsk(executionBatch,OrderType.ASK,totalPrice,fees);
        //返回dust
        _transferETH(msg.sender,address(this).balance);
    }
    /**
     * 单独出价订单
     * @param order 挂单合计
     * @param exchange 撮合订单体
     * @param takerFee 吃单手续费
     * @param signatures 挂单签名
     */
    function _takeBidSingle(
        Order memory order,
        Exchange memory exchange,
        FeeRate memory takerFee,
        bytes memory signature
    )internal {
        Fees memory fees = Fees(protocolFee,takerFee);
        Taker memory taker = exchange.taker;
        uint256 listingAmount = exchange.listing.amount;
        //验证挂单
        if(!_validateOrderAndListing(order, OrderType.BID, exchange, signature, fees)){
            revert InvalidOrder();
        }

        //创建单个执行批次
        bytes memory executionBatch = _initializeSingleExecution(order, OrderType.BID, taker.tokenId, taker.amount, order.trader);
        
        //执行token交易
        {
            bool[] memory successTransfer = _executeNonfungibleTransfers(executionBatch, 1);
            if(!successTransfer[0]){
                revert TokenTransferFailded();
            }
        }

        //计算Fees
        (
            uint256 totalPrice,
            uint256 protocolFeeAmount,
            uint256 makerFeeAmount,
            uint256 takerFeeAmount
        ) = _computeFees(exchange.listing.price, listingAmount, order.makerFee, fees);

        //pool交易
        address trader = order.trader;
        _transferPool(trader, protocolFee.recipient,protocolFeeAmount);
        _transferPool(trader, order.makerFee.recipient,makerFeeAmount);
        _transferPool(trader, takerFee.recipient,takerFeeAmount);

        unchecked {
            _transferPool(trader, msg.sender, totalPrice-takerFeeAmount-protocolFeeAmount);
            //修改状态
            amountTaken[order.trader][bytes32(order.salt)][exchange.listing.index] += listingAmount;
        }
    }
    
    function _takeAsk(
        Order[] memory orders,
        Exchange[] memory exchanges,
        FeeRate memory takerFee,
        bytes memory signature,
        address tokenRecipent
    ) internal {
        Fees memory fees = Fees(protocolFee,takerFee);
        //验证所有的orders
        (bool[] memory validOrders,uint256[][] memory pendingAmountTaken) = _validateOrders(
            order,
            orderType.Ask,
            signatures,
            fees);

        uint256 exchangesLength = exchanges.length;

        //初始化交易批次和资金结算
        (bytes memory executionBatch,FungibleTransfers memory fungibleTransfers) = _initializeBatch(exchangesLength, OrderType.ASK, tokenRecipent);
        uint256 remainingEth = address(this).balance;
        Order memory order;
        Exchange memory exchange;
        for(uint256 i;i<exchangesLength;i++){
            exchange = exchanges[i];
            order = orders[exchange.index];
            //验证Listing
            if(
                _validateListingFromBatch(
                    order,
                    OrderType.ASK,
                    exchange,
                    validOrders,
                    pendingAmountTaken
                )
            ){
                //插入数据进入execution的Transfer[]
                bool inserted;
                (remainingEth,inserted) = _insertExecutionAsk(
                    executionBatch,
                    fungibleTransfers,
                    order,
                    validOrders,
                    fees,
                    remainingEth
                );
                if(inserted){
                    pendingAmountTaken[exchange.index][exchange.listing.index] += exchange.taker.amount;
                }
            }
        }

        //执行所有交易
        _executeBatchTransfer(executionBatch,fungibleTransfers,fees,OrderType.ASK);

        //返回余额
        _transferETH(msg.sender, address(this).balance);
    }
    /*//////////////////////////////////////////////////////////////
                          EXECUTION HELPERS
    //////////////////////////////////////////////////////////////*/
    /**
     * 构建交易执行内容
     */
    function _initializeSingleExecution(
        Order memory order,
        OrderType orderType,
        uint256 tokenId,
        uint256 amount,
        address taker
    )internal pure returns(bytes memory executionBatch){
        uint256 arrayLength = Transfer_size + One_word;
        uint256 executionLength = ExecutionBatch_base_size + arrayLength;
        executionBatch = new bytes(executionLength);
        assembly {
            let executionBatchOffset := add(executionBatch,ExecutionBatch_calldata_offset)  // 偏移40位， 前32字节存储字节数组长度，后字节存储函数选择器
            mstore(add(executionBatchOffset,ExecutionBatch_taker_offset),taker)
            mstore(add(executionBatchOffset,ExecutionBatch_orderType_offset),orderType)
            mstore(add(executionBatchOffset,ExecutionBatch_transfers_pointer_offset), ExecutionBatch_transfers_offset)
            mstore(add(executionBatchOffset,ExecutionBatch_transfers_offset),1)
        }
        _insertNonfungibleTransfer(executionBatch,order,tokenId,amount);
    }
    /**
     * 初始化批量执行批次
     * @param exchangesLength 撮合交易数量
     * @param orderType 订单类型
     * @param taker 吃单者
     * @return executionBatch 交易执行批次  
     * @return fungibleTransfers 资金结算
     */
    function _initializeBatch(
        uint256 exchangesLength,
        OrderType orderType,
        address taker
    ) internal pure returns(bytes memory executionBatch,FungibleTransfers memory fungibleTransfers){
        uint256 arratLength = Transfer_size * exchangesLength + One_word;
        uint256 executionBatchLength = ExecutionBatch_base_size + arrayLength;
        executionBatch = new bytes(executionBatchLength);
        assembly {
            let calldataPointer := add(executionBatch,ExecutionBatch_calldata_offset)
            mstore(add(calldataPointer,ExecutionBatch_taker_offset),taker)
            mstore(add(calldataPointer,ExecutionBatch_orderType_offset),orderType)
            mstore(add(calldataPointer,ExecutionBatch_transfers_pointer_offset),ExecutionBatch_transfers_offset)//transfer数组内存位置
            mstore(add(calldataPointer,ExecutionBatch_length_offset),exchangesLength)
        }

        //初始化资金结算
        AtomicExecution[] memory executions = new AtomicExecution[](exchangesLength);
        //初始化Fees接受账户
        address[] memory feeRecipients = new address[](exchangesLength);
        //初始化订单创建者
        address[] memory makers = new address[](exchangesLength);
        //初始化订单创建者交易金额
        uint256[] memory makersTransfers = new uint256[](exchangesLength);
        uint256[] memory feeTransfers = new uint256[](exchangesLength);
        //初始化资金结算
        fungibleTransfers = FungibleTransfers({
            totalProtocolFee:0,
            totalSellerTransfer:0,
            totalTakerFee:0,
            feeRecipientId: 0,
            makerId:0,
            feeRecipients:feeRecipients,
            makers:makers,
            makerTransfers:makersTransfers,
            feeTransfers:feeTransfers,
            executions:executions
        });
    }
}

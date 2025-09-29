// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
import { MerkleProof } from "lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/utils/cryptography/MerkleProof.sol";
import "./Signatures.sol";
import "../struct/Structs.sol";
import "./interfaces/IValidation.sol";
contract Validation is IValidation, Signatures{
    //参数设定
    uint256 public constant _BASIS_POINTS = 10_000;
    uint256 public constant _MAX_PROTOCOL_FEE_RATE = 250;//最大费率2.5%
    //跟踪每个订单的listing的完成情况 记录已完成数量  /* amountTaken[user][orderHash][listingIndex] */
    mapping(address => mapping(bytes32 => mapping(uint256 => uint256))) public amountTaken;

    FeeRate public protocolFee;

    constructor()Signatures(){}

    /**
     * 验证提交的订单和挂单
     * @param order 订单信息
     * @param orderType 订单类型
     * @param exchange 包含交易清单的交易文件     
     * @param signature 订单的签名
     * @param fees 协议和执行的手续费
     */
    function _validateOrderAndListing(
        Order memory order,
        OrderType orderType,
        Exchange memory exchange,
        bytes memory signature,
        Fees memory fees
    )internal view returns(bool){
        return _validateOrder(order,orderType,signature,fees,0)
        && _validateListing(order,orderType,exchange)
        && amountTaken[order.trader][bytes32(order.salt)][exchange.listing.index] <= exchange.listing.amount;

    }
    /**
     * 验证订单有效性
     * @param order 订单信息
     * @param orderType 订单类型 
     * @param signatures 协议和挂单手续费
     * @param fees  协议和挂单手续费
     * @param signatureIndex  签名索引
     */
    function _validateOrder(
        Order memory order,
        OrderType orderType,
        bytes memory signatures,
        Fees memory fees,
        uint256 signatureIndex
    )private view returns(bool){
        bytes32 orderhash = _hashOrder(order,orderType);
        order.salt = uint256(orderhash);
        return _verifyAuthorization(
            order.trader,
            orderhash,
            signatures,
            signatureIndex
        )&&_checkLiveness(order)&&_checkFee(order.makerFee,fees);
    }
    /**
     * 验证批量Orders的有效性
     * @param orders 挂单数组
     * @param orderType 订单类型
     * @param signatures 签名数组
     * @param fees 平台和吃单手续费
     * @return validOrders 验证后的order有效性数组
     * @return pendingAmountTaken 已执行交易的amount数组 pendingAmountTaken[orderindex][listingindex]
     */
    function _validateOrders(
        Order[] memory orders,
        OrderType orderType,
        bytes memory signatures,
        Fees memory fees
    )private view returns(bool[] memory validOrders,uint256[][] memory pendingAmountTaken){
        uint256 ordersLength = orders.length;
        validOrders = new bool[](ordersLength);
        pendingAmountTaken = new uint256[][](ordersLength);
        for(uint256 i;i<ordersLength;){
            pendingAmountTaken[i] = new uint256[](orders[i].numberOfListings);
            validOrders[i] = _validateOrder(orders[i],orderType,signatures,fees,i);
            unchecked {
                ++i;
            }
        }

    }
    /**
     * 验证撮合订单的挂单
     * @param order 卖家订单信息
     * @param orderType 订单类型
     * @param exchange 撮合订单信息
     */
    function _validateListing(
        Order memory order,
        OrderType orderType,
        Exchange memory exchange
    )internal pure returns(bool validListing){
        Listing memory listing = exchange.listing;

        validListing = MerkleProof.verify(exchange.proof,order.listingsRoot,hashListing(listing));
        Taker memory taker = exchange.taker;
        //卖方是挂单
        if(orderType == OrderType.ASK){
            if(order.assetType == AssetType.ERC721){
                validListing = validListing && listing.amount == 1 && taker.amount ==1 ;
            }
            validListing = validListing && listing.tokenId == taker.tokenId;
        }
        else{
            if(order.assetType == AssetType.ERC721){
                validListing = validListing && taker.amount ==1 ;
            }else{
                validListing = validListing && listing.tokenId == taker.tokenId;
            }
        }
    }
    
    /**
     * 验证批次交易的listing
     * @param order 批次订单数组
     * @param orderType 订单类型
     * @param exchange 撮合交易
     * @param orderValid order验证结果数组
     * @param pendingAmountTaken 已处理未提交数量数组
     */
    function _validateListingFromBatch(
        Order memory order,
        OrderType orderType,
        Exchange memory exchange,
        bool[] memory orderValid,
        uint256[][] memory pendingAmountTaken //当前批次已处理未提交
    )internal view returns(bool _validListing){
        Listing memory listing = exchange.listing;
        uint256 takerAmount = exchange.taker.amount; //当前撮合交易要交易数量
        uint256 _amountTaken = amountTaken[order.trader][bytes32(order.salt)][listing.index];//链上已交易数量
        uint256 _pendingAmountTaken = pendingAmountTaken[exchange.index][listing.index];
        _validListing = 
            orderValid[exchange.index] &&
            _validateListing(order,orderType,exchange) && 
            _pendingAmountTaken + takerAmount <= type(uint256).max - _amountTaken && //防溢出
            _pendingAmountTaken + takerAmount + _amountTaken <= listing.amount;  //链上已处理数量 + 已处理未上链数量 + 当前交易处理数量 < listing.amount
    }

    /**
     * 验证时间有效性
     * @param order 订单信息
     */
    function _checkLiveness(
        Order memory order
    )internal view returns(bool){
        return (order.expirationTime > block.timestamp);
    }
    /**
     * 验证费率不超过_MAX_PROTOCOL_FEE_RATEX_
     * @param makerFee 创建订单的fee
     * @param fees 协议和挂单的fee
     */
    function _checkFee(
        FeeRate memory makerFee,
        Fees memory fees
    )internal pure returns(bool){
        return (makerFee.rate + fees.takerFee.rate + fees.protocolFee.rate <= _MAX_PROTOCOL_FEE_RATE);
    }
    /**
     * 获取orders的listing的执行情况
     * @param taker order 发起者
     * @param orderhash orderhash
     * @param index  listing indexId
     */
    function getamountTaken(
        address taker,
        bytes32 orderhash,
        uint256 index
    )external view returns(uint256){
        return amountTaken[taker][orderhash][index];
    }
}
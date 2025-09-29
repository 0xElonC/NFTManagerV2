// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
import "./utils/Validation.sol";
import "./interfaces/IExecutor.sol";
import {TakeAsk, TakeBid, TakeAskSingle, TakeBidSingle, Order, Exchange, Fees, FeeRate, AssetType, OrderType, Transfer, FungibleTransfers, StateUpdate, AtomicExecution, Cancel, Listing} from "./struct/Structs.sol";

contract Executor is IExecutor, Validation {
    address public _DELEGATE;
    address public _POOL;
    constructor() Validation() {}

    /**
     * 插入非同质化资产交易
     * @param executionBatch 交易执行批次
     * @param order 卖家挂单
     * @param tokenId tokenId
     * @param amount 数量
     */
    function _insertNonfungibleTransfer(
        bytes memory executionBatch,
        Order memory order,
        uint256 tokenId,
        uint256 amount
    ) internal pure returns (uint256 transferIndex) {
        assembly {
            let calldataPoint := add(
                executionBatch,
                ExecutionBatch_calldata_offset
            )
            transferIndex := mload(
                add(calldataPoint, ExecutionBatch_length_offset)
            ) //获取Transcfer数组长度
            let transferOffset := mload(
                add(calldataPoint, ExecutionBatch_calldata_offset)
            ) //获取动态数组内存指针
            let transferPoint := add(
                add(calldataPoint, add(transferOffset, One_word)),
                mul(transferIndex, Transfer_size)
            )
            mstore(
                add(transferPoint, Transfer_trader_offset),
                mload(add(order, Order_trader_offset))
            ) //set the trader
            mstore(
                add(transferPoint, Transfer_collection_offset),
                mload(add(order, Order_collection_offset))
            ) //set the collection
            mstore(add(transferPoint, Transfer_id_offset), tokenId) //set the tokenId
            mstore(
                add(transferPoint, Transfer_assetType_offset),
                mload(add(order, Order_assetType_offset))
            ) //set the asset
            mstore(
                add(calldataPoint, ExecutionBatch_length_offset),
                add(transferIndex, 1)
            ) //ExecutionBatch 的 length + 1
            //如果是ERC1155再将amount写入
            if eq(
                mload(add(order, Order_assetType_offset)),
                AssetType_ERC1155
            ) {
                mstore(add(transferPoint, Transfer_amount_offset), amount)
            }
        }
    }
    /**
     * 插入同质化代币交易批次，添加fungibleTransfer中的execution（描述一次完整资金结算）
     * @param fungibleTransfers 同质化代币交易资金结算
     * @param takerAmount 交易数量  
     * @param listing 撮合的卖家挂单
     * @param orderHash listing的哈希
     * @param index 记录的交易在当前交易批次的索引
     * @param totalPrice 总交易金额
     * @param protocolFeeAmount 平台手续费
     * @param makerFeeAmount 挂单手续费
     * @param takerFeeAmount 吃饭手续费
     * @param makerIsSeller 挂单是否为卖单
     */
    function _insertFungibleTransfers(
        FungibleTransfers memory fungibleTransfers,
        uint256 takerAmount,
        Listing memory listing,
        bytes32 orderHash,
        uint256 index,
        uint256 totalPrice,
        uint256 protocolFeeAmount,
        uint256 makerFeeAmount,
        uint256 takerFeeAmount,
        bool makerIsSeller
    ) internal pure{
        uint256 makerId = fungibleTransfers.makerId;
        fungibleTransfers.executions[index].makerId = makerId;
        fungibleTransfers.executions[index].makerFeeRecipientId = fungibleTransfers.feeRecipientId;
        fungibleTransfers.executions[index].stateUpdate = StateUpdate({
            trader:fungibleTransfers.makers[makerId],
            hash:orderHash,
            index:listing.index,
            value:takerAmount,
            maxAmount:listing.amount
        });
        if( makerIsSeller ){
            fungibleTransfers.executions[index].sellerAmount = totalPrice - makerFeeAmount - protocolFeeAmount;
        }else{
            fungibleTransfers.executions[index].sellerAmount = totalPrice - takerFeeAmount - protocolFeeAmount;
        }

        fungibleTransfers.executions[index].makerFeeAmount = makerFeeAmount;
        fungibleTransfers.executions[index].takerFeeAmount = takerFeeAmount;
        fungibleTransfers.executions[index].protocolFeeAmount = protocolFeeAmount;
    }
    /**
     * 写入交易批次信息
     * @param executionBatch 空交易批次
     * @param fungibleTransfers 资金结算
     * @param order 挂单订单
     * @param exchange 撮合交易
     * @param fees 交易手续费(平台+吃饭)
     * @param remainingETH 账户余额
     * @return 账户余额
     * @return 有效交易存入成功
     */
    function _insertExecutionAsk(
        bytes memory executionBatch,
        FungibleTransfers memory fungibleTransfers,
        Order memory order,
        Exchange memory exchange,
        Fees memory fees,
        uint256 remainingETH
    )internal view returns(uint256 , bool){
        uint256 takerAmount = exchange.taker.amount;
        //计算fee
        (
            uint256 totalPrice,
            uint256 protocolFeeAmount,
            uint256 makerFeeAmount,
            uint256 takerFeeAmount
        ) = _computeFees(exchange.listing.price, takerAmount, order.makerFee, fees);

        if(totalPrice + takerFeeAmount <= remainingETH){
            //修改状态
            unchecked {
                remainingETH = remainingETH - totalPrice - takerFeeAmount;
            }

            _setAddress(fungibleTransfers, order);

            //插入非同质化交易
            uint256 transferIndex = _insertNonfungibleTransfer(
                executionBatch,
                order,
                exchange.listing.tokenId,
                takerAmount
            );
            //插入代币交易 

            _insertFungibleTransfers(
                fungibleTransfers,
                takerAmount,
                exchange.listing,
                bytes32(order.salt),
                transferIndex,
                totalPrice,
                protocolFeeAmount,
                makerFeeAmount,
                takerFeeAmount,
                true
            );
            return (remainingETH,true);
        }else{
            return (remainingETH,false);
        }
    }

    /**
     * 计算Fees费用
     * @param perTokenPrice 单个token的价格
     * @param takerAmount  token的数量
     * @param makerFees  挂单创建者Fee
     * @param fees 平台协议fee和吃单者fee
     * @return totalPrice  总金额
     * @return protocolFeeAmount  协议fee金额
     * @return makerFeeAmount 挂单fee金额
     * @return takerFeeAmount  吃单fee金额
     */
    function _computeFees(
        uint256 perTokenPrice,
        uint256 takerAmount,
        FeeRate memory makerFees,
        Fees memory fees
    )
        internal
        pure
        returns (
            uint256 totalPrice,
            uint256 protocolFeeAmount,
            uint256 makerFeeAmount,
            uint256 takerFeeAmount
        )
    {
        totalPrice = perTokenPrice * takerAmount;
        protocolFeeAmount = (totalPrice * fees.protocolFee.rate) / _BASIS_POINTS;
        makerFeeAmount = (totalPrice * makerFees.rate) / _BASIS_POINTS;
        takerFeeAmount = (totalPrice * fees.takerFee.rate) / _BASIS_POINTS;
    }

    function _setAddress(
        FungibleTransfers memory fungibleTransfer,
        Order memory order
    ) internal pure {   
        uint256 feeRecipientId = fungibleTransfer.feeRecipientId;
        address currentfeeRecipient = fungibleTransfer.feeRecipients[feeRecipientId];
        address feeRecipient = order.makerFee.recipient;
        if(currentfeeRecipient != feeRecipient){
            if(currentfeeRecipient == address(0)){
                fungibleTransfer.feeRecipients[feeRecipientId] = feeRecipient;
            }else{
                unchecked {
                    fungibleTransfer.feeRecipients[++feeRecipientId] = feeRecipient;
                }
                fungibleTransfer.feeRecipientId = feeRecipientId;
            }
        }
        
        uint256 makerId = fungibleTransfer.makerId;
        address currentMaker = fungibleTransfer.makers[makerId];
        address maker = order.trader;
        if(maker != currentMaker){
            if( currentMaker == address(0) ){
                fungibleTransfer.makers[makerId] = maker;
            }else{
                unchecked {
                    fungibleTransfer.makers[++makerId] = maker;
                }
                fungibleTransfer.makerId = makerId;
            }
        }
    } 

    /**
     * 执行交易非同质化资产
     * @param executionBatch 交易批次
     * @param index 索引
     */
    function _executeNonfungibleTransfers(
        bytes memory executionBatch,
        uint256 index
    ) internal returns (bool[] memory) {
        address delegate = _DELEGATE;
        uint256 successTransfersPointer;
        assembly {
            successTransfersPointer := mload(Memory_pointer)
            mstore(Memory_pointer, add(successTransfersPointer, One_word))
        }

        bool[] memory successTransfers = new bool[](index);

        assembly {
            let size := mload(executionBatch)
            let selectPoint := add(
                executionBatch,
                ExecutionBatch_selector_offset
            )
            mstore(selectPoint, shr(Bytes4_shift, Delegate_transfer_selector))
            let calldataPoint := add(
                selectPoint,
                Delegate_transfer_calldata_offset
            )
            let success := call(
                gas(),
                delegate,
                0,
                calldataPoint, //传参起始地址
                sub(size, Delegate_transfer_calldata_offset),
                successTransfersPointer,
                add(0x40, mul(index, One_word))
            )
        }
        return successTransfers;
    }

   function _executeBatchTransfer(
        bytes memory executionBatch,
        FungibleTransfers memory fungibleTransfers,
        Fees memory fees,
        OrderType orderType
    ) internal {
        uint256 batchLength;
        assembly {
            let calldataPointer := add(executionBatch, ExecutionBatch_calldata_offset)
            batchLength := mload(add(calldataPointer, ExecutionBatch_length_offset))
        }
        if (batchLength > 0) {
            bool[] memory successfulTransfers = _executeNonfungibleTransfers(
                executionBatch,
                batchLength
            );

            uint256 transfersLength = successfulTransfers.length;
            for (uint256 i; i < transfersLength; ) {
                if (successfulTransfers[i]) {
                    AtomicExecution memory execution = fungibleTransfers.executions[i];
                    FeeRate memory makerFee;
                    uint256 price;
                    unchecked {
                        if (orderType == OrderType.ASK) {
                            fungibleTransfers.makerTransfers[execution.makerId] += execution
                                .sellerAmount; // amount that needs to be sent *to* the order maker
                            price =
                                execution.sellerAmount +
                                execution.protocolFeeAmount +
                                execution.makerFeeAmount;
                        } else {
                            fungibleTransfers.makerTransfers[execution.makerId] +=
                                execution.protocolFeeAmount +
                                execution.makerFeeAmount +
                                execution.takerFeeAmount +
                                execution.sellerAmount; // amount that needs to be taken *from* the order maker
                            price =
                                execution.sellerAmount +
                                execution.protocolFeeAmount +
                                execution.takerFeeAmount;
                        }
                        fungibleTransfers.totalSellerTransfer += execution.sellerAmount; // only for bids
                        fungibleTransfers.totalProtocolFee += execution.protocolFeeAmount;
                        fungibleTransfers.totalTakerFee += execution.takerFeeAmount;
                        fungibleTransfers.feeTransfers[execution.makerFeeRecipientId] += execution
                            .makerFeeAmount;
                        makerFee = FeeRate(
                            fungibleTransfers.feeRecipients[execution.makerFeeRecipientId],
                            uint16((execution.makerFeeAmount * _BASIS_POINTS) / price)
                        );
                    }

                    /* Commit state updates. */
                    StateUpdate memory stateUpdate = fungibleTransfers.executions[i].stateUpdate;
                    {
                        address trader = stateUpdate.trader;
                        bytes32 hash = stateUpdate.hash;
                        uint256 index = stateUpdate.index;
                        uint256 _amountTaken = amountTaken[trader][hash][index];
                        uint256 newAmountTaken = _amountTaken + stateUpdate.value;

                        /* Overfulfilled Listings should be caught prior to inserting into the batch, but this check prevents any misuse. */
                        if (newAmountTaken <= stateUpdate.maxAmount) {
                            amountTaken[trader][hash][index] = newAmountTaken;
                        } else {
                            revert OrderFulfilled();
                        }
                    }

                    _emitExecutionEventFromBatch(
                        executionBatch,
                        price,
                        makerFee,
                        fees,
                        stateUpdate,
                        orderType,
                        i
                    );
                }

                unchecked {
                    ++i;
                }
            }

            if (orderType == OrderType.ASK) {
                /* Transfer the payments to the sellers. */
                uint256 makersLength = fungibleTransfers.makerId + 1;
                for (uint256 i; i < makersLength; ) {
                    _transferETH(fungibleTransfers.makers[i], fungibleTransfers.makerTransfers[i]);
                    unchecked {
                        ++i;
                    }
                }

                /* Transfer the fees to the fee recipients. */
                uint256 feesLength = fungibleTransfers.feeRecipientId + 1;
                for (uint256 i; i < feesLength; ) {
                    _transferETH(
                        fungibleTransfers.feeRecipients[i],
                        fungibleTransfers.feeTransfers[i]
                    );
                    unchecked {
                        ++i;
                    }
                }

                /* Transfer the protocol fees. */
                _transferETH(fees.protocolFee.recipient, fungibleTransfers.totalProtocolFee);

                /* Transfer the taker fees. */
                _transferETH(fees.takerFee.recipient, fungibleTransfers.totalTakerFee);
            } else {
                /* Take the pool funds from the buyers. */
                uint256 makersLength = fungibleTransfers.makerId + 1;
                for (uint256 i; i < makersLength; ) {
                    _transferPool(
                        fungibleTransfers.makers[i],
                        address(this),
                        fungibleTransfers.makerTransfers[i]
                    );
                    unchecked {
                        ++i;
                    }
                }

                /* Transfer the payment to the seller. */
                _transferPool(address(this), msg.sender, fungibleTransfers.totalSellerTransfer);

                /* Transfer the fees to the fee recipients. */
                uint256 feesLength = fungibleTransfers.feeRecipientId + 1;
                for (uint256 i; i < feesLength; ) {
                    _transferPool(
                        address(this),
                        fungibleTransfers.feeRecipients[i],
                        fungibleTransfers.feeTransfers[i]
                    );
                    unchecked {
                        ++i;
                    }
                }

                /* Transfer the protocol fees. */
                _transferPool(
                    address(this),
                    fees.protocolFee.recipient,
                    fungibleTransfers.totalProtocolFee
                );

                /* Transfer the taker fees. */
                _transferPool(
                    address(this),
                    fees.takerFee.recipient,
                    fungibleTransfers.totalTakerFee
                );
            }
        }
    }


    /*//////////////////////////////////////////////////////////////
                        TRANSFER FUNCTIONS
        //////////////////////////////////////////////////////////////*/

    function _transferETH(address to, uint256 amount) internal {
        bool success;
        if (amount > 0) {
            assembly {
                success := call(gas(), to, amount, 0, 0, 0, 0)
            }
            if (!success) {
                revert transferETHFailded();
            }
        }
    }

    function _transferPool(address from, address to, uint256 amount) internal {
        bool success;
        address pool = _POOL;
        if(amount > 0){
            assembly {
                let transferPoint := mload(Memory_pointer)
                mstore(transferPoint,ERC20_transferFrom_selector)
                mstore(add(transferPoint,ERC20_transferFrom_from_offset),from)
                mstore(add(transferPoint,ERC20_transferFrom_to_offset),to)
                mstore(add(transferPoint,ERC20_transferFrom_amount_offset),amount)
                success := call(
                    gas(),
                    pool,
                    0,
                    transferPoint,
                    ERC20_transferFrom_size,
                    0,
                    0
                )
            }
        }
    }
}

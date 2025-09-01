// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
import "./utils/Validation.sol";
import "./interfaces/IExecutor.sol";
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

contract Executor is IExecutor,Validation{
        address public _DELEGATE;
        constructor()Validation(){
        }
        /**
         * 插入非同质化资产交易
         */
        function _insertNonfungibleTransfer(
            bytes memory executionBatch,
            Order memory order,
            uint256 tokenId,
            uint256 amount
        )internal pure returns(uint256 transferIndex){
            assembly {
                let calldataPoint := add(executionBatch,ExecutionBatch_calldata_offset)
                transferIndex := mload(add(calldataPoint,ExecutionBatch_length_offset))//获取Transcfer数组长度
                let transferOffset := mload(add(calldataPoint,ExecutionBatch_calldata_offset))//获取动态数组内存指针
                let transferPoint := add(
                    add(calldataPoint,add(transferOffset,One_word)),
                    mul(transferIndex,Transfer_size)
                    )   
                mstore(
                    add(transferPoint,Transfer_trader_offset),
                    mload(add(order,Order_trader_offset))
                )//set the trader
                mstore(
                    add(transferPoint,Transfer_collection_offset),
                    mload(add(order,Order_collection_offset))
                )//set the collection
                mstore(
                    add(transferPoint,Transfer_id_offset),
                    tokenId
                )//set the tokenId
                mstore(
                    add(transferPoint,Transfer_assetType_offset),
                    mload(add(order,Order_assetType_offset))
                )//set the asset
                mstore(
                    add(calldataPoint,ExecutionBatch_length_offset),
                    add(transferIndex,1)
                )//ExecutionBatch 的 length + 1
                //如果是ERC1155再将amount写入
                if eq(mload(add(order,Order_assetType_offset)),AssetType_ERC1155){
                    mstore(
                        add(transferPoint,Transfer_amount_offset),
                        amount
                    )
                }
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
        )internal pure returns(
            uint256 totalPrice,
            uint256 protocolFeeAmount,
            uint256 makerFeeAmount,
            uint256 takerFeeAmount
        ){
            totalPrice = perTokenPrice * takerAmount;
            protocolFeeAmount = (totalPrice * fees.protocolFee.rate) / _BASIC_POINT;
            makerFeeAmount = (totalPrice * makerFees.rate) / _BASIC_POINT;
            takerFeeAmount = (totalPrice * fees.takerFee.rate) / _BASIC_POINT;
        }

        function _executeNonfungibleTransfers(
            bytes memory executionBatch,
            uint256 index
        )internal returns(bool[] memory){
            address delegate = _DELEGATE;
            uint256 successTransfersPointer;
            assembly {
                successTransfersPointer := mload(Memory_pointer)
                mstore(Memory_pointer,add(successTransfersPointer,One_word))
            }

            bool[] memory successTransfers = new bool[](index);

            assembly {
                let size := mload(executionBatch)
                let selectPoint := add(executionBatch,ExecutionBatch_selector_offset)
                let calldataPoint := add(executionBatch,ExecutionBatch_calldata_offset)
                mstore(selectPoint,shr(Bytes4_shift,Delegate_transfer_selector))
                let success := call(
                    gas(),
                    delegate,
                    0,
                    calldataPoint,//传参起始地址
                    sub(size,calldataPoint),
                    successTransfersPointer,
                    add(0x40,mul(index,One_word))
                )
            }
            return successTransfers;
        }
        /*//////////////////////////////////////////////////////////////
                        TRANSFER FUNCTIONS
        //////////////////////////////////////////////////////////////*/

        function _transferETH(
            address to,
            uint256 amount
        )internal {
            bool success;
            if(amount>0){
                assembly {
                    success := call(gas(),to,amount,0,0,0,0)
                }
            }
            if(!success){
                revert transferETHFailded();
            }
        }
}
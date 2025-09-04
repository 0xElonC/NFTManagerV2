// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
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
} from "../struct/Structs.sol";
interface IXYDExchangeV2 {
    
    /*//////////////////////////////////////////////////////////////
                          ERROR
    //////////////////////////////////////////////////////////////*/

    error InvalidOrder(); //订单错误
    error InsufficientFunds(); //余额不足
    error TokenTransferFailded();//token转账失败

    event SetGovernor(address governor);
    event SetDelegate(address delegate);
    event SetPool(address pool);

    function initialize(address ownerAddress, address delegateAddress, address poolAddress) external;
    function setGovernor(address governor) external;
    function getGovernor()external returns (address);
    function getDelegate() external view returns (address);
    function setDelegate(address delegate) external;
    function getPool() external view returns (address); 
    function setPool(address pool) external;
    ///test
    function getOrderType()external view returns(bytes32);
    function getFeeType()external view returns(bytes32);
    function getDomainSeparator()external view returns(bytes32);
    /*//////////////////////////////////////////////////////////////
                          EXECUTION WRAPPERS
    //////////////////////////////////////////////////////////////*/
    //function takeAskSingle(TakeAskSingle memory inputs,bytes calldata oracleSignature)external payable;
    function takeAskSingle(TakeAskSingle memory inputs)external payable;
    function takeBidSingle(TakeBidSingle memory inputs)external payable;

}
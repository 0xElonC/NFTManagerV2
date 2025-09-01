// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IValidation {
        function getamountTaken(address taker,bytes32 orderhash,uint256 index)external view returns(uint256);
}
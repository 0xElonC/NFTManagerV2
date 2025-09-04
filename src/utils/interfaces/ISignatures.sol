// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ISignatures {
    error ExpiredOracleSignature();//oracle签名过期
    error UnautorizedOracle();//oracle地址无效
    error InvalidOracleSignature();//oracle签名错误
}
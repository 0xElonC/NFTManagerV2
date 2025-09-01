// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
import "../struct/Constants.sol";
import "./interfaces/Isignatures.sol";
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
contract Signatures is ISignatures {
    string private constant _NAME = "XYD Exchange";
    string private constant _VERSION = "3.0";

    bytes32 public  _DOMAIN_SEPARATOR;
    bytes32 public  _ORDER_TYPEHASH;
    bytes32 public  _FEE_TYPEHASH;

    mapping(address => uint256) public oracles;
    mapping(address => uint256) public nonces;
    uint256 public blockRange;//区块范围
    constructor() {}
    
    function verifyDomain()public pure returns(bytes32 EIP712DomainTypehash){
        EIP712DomainTypehash = keccak256(            
            bytes.concat(
                "EIP712Domain(",
                "string name,",
                "string version,",
                "uint256 chainId,",
                "address verifyingContract",
                ")"
            )
        );
    }

    /**
     * 获取 version 和 domainSeparator
     * @return version 
     * @return domainSeparator 
     */
    function information() external view returns(string memory version,bytes32 domainSeparator){
        version = _VERSION;
        domainSeparator = _DOMAIN_SEPARATOR;
    }
    /**
     * 创建EIP712类型结构体哈希
     * @param proxy 代理合约地址
     * @return domainSeparator 
     * @return orderTypeHash 
     * @return feeTypeHash 
     */
    function _createTypeHash(address proxy) internal view returns(
        bytes32 domainSeparator,
        bytes32 orderTypeHash,
        bytes32 feeTypeHash
    ){
        bytes32 eip712domainTypeHash = keccak256(
            bytes.concat(
                "EIP712Domain(",
                "string name,",
                "string version,",
                "uint256 chainId,",
                "address verifyingContract",
                ")"
            )
        );
        bytes memory feeRateTypestring = "FeeRate(address recipient,uint16 rate)";
        bytes memory orderTypestring = "Order(address trader,address collection,bytes32 listingsRoot,uint256 numberOfListings,uint256 expirationTime,uint8 assetType,FeeRate makerFee,uint256 salt,uint8 orderType,uint256 nonce)";

        domainSeparator = _hashDomain(
            eip712domainTypeHash,
            keccak256(bytes(_NAME)),
            keccak256(bytes(_VERSION)),
            proxy
        );

        orderTypeHash = keccak256(
            bytes.concat(orderTypestring,feeRateTypestring)
        );
        
        feeTypeHash = keccak256(feeRateTypestring);
    }

    /**
     * 得到EIP712 DOMAIN哈希
     * @param eip712domainTypeHash eip712结构体类型哈希
     * @param name name哈希
     * @param version version哈希
     * @param proxy 代理地址
     */
    function _hashDomain(
        bytes32 eip712domainTypeHash,
        bytes32 name,
        bytes32 version,
        address proxy
    )private view returns(bytes32){
        return keccak256(abi.encode(
            eip712domainTypeHash,
            name,
            version,
            block.chainid,
            proxy   
        ));
    }
    /**
     * 获取EIP712签名信息
     * @param orderhash 订单哈希
     */
    function _hashToSign(
        bytes32 orderhash
    )internal view returns(bytes32){
        return keccak256(
            bytes.concat(
                bytes2(0x1901),
                _DOMAIN_SEPARATOR,
                orderhash)
        );
    }
    /**
     * 生成order哈希
     * @param order 挂单订单集合
     * @param orderType 挂单类型
     */
    function _hashOrder(
        Order memory order,
        OrderType orderType
    )public view returns(bytes32){
        return keccak256(
            abi.encode(
                _ORDER_TYPEHASH,
                order.trader,
                order.collection,
                order.listingsRoot,
                order.numberOfListings,
                order.expirationTime,
                order.assetType,
                _hashFeeRate(order.makerFee),
                order.salt,
                orderType,
                nonces[order.trader]
            )
        );
    }

    /**
     * 生成feeRate哈希
     * @param feeRate fee信息
     */
    function _hashFeeRate(
        FeeRate memory feeRate
    )public view returns(bytes32){
        return keccak256(
            abi.encode(
                _FEE_TYPEHASH,
                feeRate.recipient,
                feeRate.rate
            )
        );
    }
    /**
     * 获取listing哈希
     * @param listing 某个NFT挂单信息
     */
    function hashListing(Listing memory listing)public pure returns(bytes32){
        return keccak256(abi.encode(
            listing.index,
            listing.tokenId,
            listing.amount,
            listing.price
        ));
    }

    /**
     * 使用已获授权的调用者对合约数据创建哈希值
     * @param _caller 调用者地址
     */
    function _hashCalldata(address _caller)internal pure returns(bytes32 hash){
        assembly {
            let freePoint := mload(0x40)
            let size := add(sub(freePoint,0x80),0x20)
            mstore(freePoint,_caller)
            hash := keccak256(0x80,size)
        }
    }
    /**
     * 验证Oracle签名
     */
    modifier verifyOracleSignature(bytes32 hash,bytes calldata oracleSignature){
        bytes32 r;
        bytes32 s;
        uint8 v;
        uint32 blockNumber;
        address oracle;
        assembly {
            let signatureOffset := oracleSignature.offset
            r := calldataload(signatureOffset)
            s := calldataload(add(signatureOffset,Signatures_s_offset))
            v := shr(Bytes1_shift,calldataload(add(signatureOffset,Signatures_v_offset)))
            blockNumber := shr(
                Bytes4_shift,calldataload(add(signatureOffset,OracleSignatures_blockNumber_offset))
            )
            oracle := shr(
                Bytes20_shift,calldataload(add(signatureOffset,OracleSignatures_oracle_offset))
            )
        }
        if(blockNumber + blockRange < block.number){
            revert ExpiredOracleSignature();
        }
        if(oracles[oracle] == 0){
            revert UnautorizedOracle();
        }
        if(!_verify(oracle,keccak256(abi.encodePacked(hash,blockNumber)),v,r,s)){
            revert InvalidOracleSignature();
        }
        _;
    } 

    /**
     * 验证EIP712签名
     * @param signer 签名地址  
     * @param orderhash 订单哈希
     * @param signatures 签名信息数组
     * @param signaturesIndex 签名索引  
     */
    function _verifyAuthorization(
        address signer,
        bytes32 orderhash,
        bytes memory signatures,
        uint256 signaturesIndex
    ) internal view returns(bool authorized){
        bytes32 hashToSign = _hashToSign(orderhash);
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly{
            let signatureOffset := add(add(signatures,One_word),mul(Signatures_size,signaturesIndex))
            r := mload(signatureOffset)
            s := mload(add(signatureOffset,Signatures_s_offset))
            v := shr(Bytes1_shift,mload(add(signatureOffset,Signatures_v_offset)))
        }
        authorized = _verify(signer,hashToSign,v,r,s);
    }

    /**
     * 验证签名 v ,r ,s ，验证是否是签名者签名
     * @param signer 签名者
     * @param hashToSign 签名数据
     * @param v v
     * @param r r
     * @param s s
     */
    function _verify(
        address signer,
        bytes32 hashToSign,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) private pure returns(bool valid){
        address recoveredSigner = ecrecover(hashToSign, v, r, s);
        if(recoveredSigner != address(0) && recoveredSigner == signer){
            valid = true;
        }
    }
}
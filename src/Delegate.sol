// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {OrderType, Transfer} from "./struct/Structs.sol";
import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "./struct/Constants.sol";
contract Delegate is Ownable{
    error Unauthorized();
    error InvaildTransfer();
    mapping(address => bool) public contracts;
     mapping(address => bool) public revokedApproval;
    constructor(address initialOwner) Ownable(initialOwner) {}

    modifier onlyApproved() {
        if ( contracts[msg.sender] != true) {
            revert Unauthorized();
        }
        _;
    }

    event ApproveContract(address indexed _contract);
    event ContractDenied(address indexed _contract);

    event RevokeApproval(address indexed user);
    event GrantApproval(address indexed user);

        /**
     * @dev Approve contract to call transfer functions
     * @param _contract address of contract to approve
     */
    function approveContract(address _contract) external onlyOwner {
        contracts[_contract] = true;
        emit ApproveContract(_contract);
    }

    /**
     * @dev Revoke approval of contract to call transfer functions
     * @param _contract address of contract to revoke approval
     */
    function denyContract(address _contract) external onlyOwner {
        contracts[_contract] = false;
        emit ContractDenied(_contract);
    }

    /**
     * @dev Block contract from making transfers on-behalf of a specific user
     */
    function revokeApproval() external {
        revokedApproval[msg.sender] = true;
        emit RevokeApproval(msg.sender);
    }

    /**
     * @dev Allow contract to make transfers on-behalf of a specific user
     */
    function grantApproval() external {
        revokedApproval[msg.sender] = false;
        emit GrantApproval(msg.sender);
    }

    function transfer(
        address taker,
        OrderType ordertype,
        Transfer[] calldata transfers,
        uint256 length
    ) external onlyApproved returns (bool[] memory successTransfer) {
        if (transfers.length < length) {
            revert InvaildTransfer();
        }
        successTransfer = new bool[](length);
        for (uint256 i = 0; i < length;) {
            assembly {
                let calldataPoint := mload(0x40)
                let transferPoint := add(transfers.offset, mul(Transfer_size, i))
                let assetType := calldataload(
                    add(transferPoint, Transfer_assetType_offset)
                )
                switch assetType
                case 0 {
                    //ERC721
                    mstore(calldataPoint, ERC721_safeTransferFrom_selector)
                    switch ordertype
                    case 0 {
                        //Ask
                        mstore(
                            add(
                                calldataPoint,
                                ERC721_safeTransferFrom_to_offset
                            ),
                            taker
                        )
                        mstore(
                            add(
                                calldataPoint,
                                ERC721_safeTransferFrom_from_offset
                            ),
                            calldataload(
                                add(transferPoint, Transfer_trader_offset)
                            )
                        )
                    }
                    case 1 {
                        //Bid
                        mstore(
                            add(
                                calldataPoint,
                                ERC721_safeTransferFrom_from_offset
                            ),
                            taker
                        )
                        mstore(
                            add(
                                calldataPoint,
                                ERC721_safeTransferFrom_to_offset
                            ),
                            calldataload(
                                add(transferPoint, Transfer_trader_offset)
                            )
                        )
                    }
                    mstore(
                        add(calldataPoint, ERC721_safeTransferFrom_id_offset),
                        calldataload(add(transferPoint, Transfer_id_offset))
                    )

                    let collection := calldataload(
                        add(transferPoint, Transfer_collection_offset)
                    )

                    let success := call(
                        gas(),
                        collection,
                        0,
                        calldataPoint,
                        ERC721_safeTransferFrom_size,
                        0,
                        0
                    )
                    mstore(
                        add(add(successTransfer, 0x20), mul(0x20, i)),
                        success
                    )
                }
                default{
                    revert(0,0)
                }
            }
            unchecked {
                ++i;
            }
        }
    }
}

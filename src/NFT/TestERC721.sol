// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC721} from "lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

contract TestERC721 is ERC721,Ownable  {

    uint256 public currentTokenId;

    constructor(
        string memory name,
        string memory symbol, 
        address initialOwner) ERC721(name, symbol) Ownable(initialOwner) {
            currentTokenId = 1;
        }

    event mintNFT(address indexed to,uint256 indexed tokenId);
    event transferSuccess(address indexed from,address indexed to,uint256 tokenId);
    event approveSuccess(address indexed to,uint256 indexed tokenId);

    function mint(address to) external onlyOwner returns(uint256){
        uint256 tokenId = currentTokenId;
        _safeMint(to, tokenId);
        currentTokenId++;
        emit mintNFT(to,tokenId);
        return tokenId;
    }

   function transferNFT(address from,address to,uint256 tokenId)external{
        require(isApprovedForAll(from, msg.sender),"no permission");
        _transfer(from, to, tokenId);
   }


    function approveNFT(address to,uint256 tokenId)external{
        require(_ownerOf(tokenId) == msg.sender,"not Owner");
        approve(to, tokenId);
    }

    function approveALL(address to,bool approved) external{
        setApprovalForAll(to, approved);
    }

    function totalSupply()external view returns(uint256){
        return currentTokenId;
    }
}
// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity >=0.7.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "hardhat/console.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

pragma abicoder v2;

contract ERC721Merchant is
    ERC721URIStorage,
    AccessControl
{
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    constructor(
        string memory tknName,
        string memory tknSymbol,
        address minter
    ) ERC721(tknName, tknSymbol) {
        if (minter != address(0)) {
            _setupRole(MINTER_ROLE, minter);
        }
    }

    function supportsInterface(bytes4 interfaceId)
        public
        virtual
        override(AccessControl, ERC721)
        view
        returns (bool)
    {
        return
            ERC721.supportsInterface(interfaceId) ||
            AccessControl.supportsInterface(interfaceId);
    }

    function mint(
        address minter,
        uint256 tokenId,
        string memory uri
    ) public returns (bool) {
        require(
            hasRole(MINTER_ROLE, msg.sender),
            "invalid or unauthorized"
        );
        require(
            hasRole(MINTER_ROLE, minter),
            "invalid or unauthorized"
        );
        _mint(minter, tokenId);
        _setTokenURI(tokenId, uri);
        return true;
    }
}

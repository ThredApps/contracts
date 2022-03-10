interface IERC721Merchant is IERC721{
    function mint(address minter, uint256 tokenId, string memory uri) external returns (bool);
}
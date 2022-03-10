interface IERC721Merchant{
    function mint(address minter, uint256 tokenId, string memory uri) external returns (bool);
}
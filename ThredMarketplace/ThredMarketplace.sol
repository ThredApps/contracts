// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity >=0.7.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

import "hardhat/console.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@thredapps/contracts/ERC721Merchant/ERC721Merchant.sol";

pragma abicoder v2;

contract ThredMarketplace is
    ReentrancyGuard,
    EIP712
{
    using Counters for Counters.Counter;
    using SafeMath for uint256;
    Counters.Counter private _itemIds;

    struct MarketItem {
        uint256 itemId;
        address nftContract;
        uint256 tokenId;
        address payable seller;
        address payable owner;
        uint256 price;
        bool forSale;
        uint256 royalty;
        address tokenContract;
        bool isNative;
        bool minted;
    }

    struct NFTVoucher {
        uint256 tokenId;
        uint256 minPrice;
        uint256 royalty;
        address token;
        bool isNative;
        string uri;
        bytes signature;
    }

    event Sale(
        uint256 indexed price,
        address indexed from,
        address indexed to,
        uint256 indexed tokenId
    ) anonymous;

    event ListedNFT(
        address indexed contractId,
        uint256 indexed price,
        address indexed from,
        uint256 indexed tokenId
    ) anonymous;

    mapping(uint256 => MarketItem) private idToMarketItem;

    function mintAndTransfer(NFTVoucher calldata voucher, address contractAddress)
        public
        nonReentrant
        returns (bool)
    {
        require(voucher.minPrice > 0, "Price must be at least 1 wei");
        address signer = _verify(voucher);

        IERC721Merchant nft = IERC721Merchant(contractAddress);

        nft.mint(signer, voucher.tokenId, voucher.uri);
        
        createMarketItem(payable(signer), payable(msg.sender), contractAddress, voucher);

        uint256 itemId = _itemIds.current();
        
        return createSale(idToMarketItem[itemId]);
    }

    function mintAndTransferCustom(NFTVoucher calldata voucher, address contractAddress)
        public
        payable
        nonReentrant
        returns (bool)
    {
        return mintAndTransfer(voucher, contractAddress);
    }

    function createSale(MarketItem memory item) public nonReentrant returns (bool) {
        require(item.price > 0, "Price must be at least 1 wei");
        require(
            item.price == idToMarketItem[item.itemId].price,
            "Price must match"
        );
        require(
            item.tokenId == idToMarketItem[item.itemId].tokenId,
            "Token must match"
        );
        MarketItem storage currentItem = idToMarketItem[item.itemId];
        require(currentItem.forSale == true, "Not for sale");
        address walletAddress = getThredAddress();
        address seller = currentItem.seller;
        uint256 price = currentItem.price;
        uint256 royalty = currentItem.royalty;
        uint256 fee = calculateFee(price, 3);
        uint256 royalties = calculateFee(price, royalty);
        uint256 calculated = calculateFee(price, 97 - royalty);
        address owner = currentItem.owner;

        IERC721 nft = IERC721(currentItem.nftContract);

        if (currentItem.isNative || currentItem.tokenContract == address(0)){
            payable(seller).transfer(calculated);
            payable(walletAddress).transfer(fee);
        }
        else{
            IERC20 paymentToken = IERC20(currentItem.tokenContract);
            if (
                paymentToken.allowance(msg.sender, address(this)) >=
                currentItem.price
            ) {
                require(
                    paymentToken.transferFrom(msg.sender, seller, calculated),
                    "transfer Failed"
                );
                require(
                    paymentToken.transferFrom(msg.sender, walletAddress, fee),
                    "transfer Failed"
                );
                require(
                    paymentToken.transferFrom(msg.sender, owner, royalties),
                    "transfer Failed"
                );
            } else {
                revert("Insufficient Allowance");
            }
        }
        // emit Sale(price, seller, msg.sender, currentItem.tokenId);
        nft.transferFrom(seller, msg.sender, currentItem.tokenId);
        idToMarketItem[item.itemId].seller = payable(msg.sender);
        idToMarketItem[item.itemId].forSale = false;
        return true;
    }

    function createSaleCustom(MarketItem memory item)
        public
        payable
        nonReentrant
        returns (bool)
    {
        return createSale(item);
    }

    function calculateFee(uint256 _num, uint256 percentWhole)
        internal
        pure
        returns (uint256)
    {
        uint256 onePercentofTokens = _num.mul(100).div(100 * 10**uint256(2));
        uint256 twoPercentOfTokens = onePercentofTokens.mul(percentWhole);
        return twoPercentOfTokens;
    }

    constructor(
        string memory domain,
        string memory version
    ) EIP712(domain, version) {
    }

    function getThredAddress() internal pure returns (address) {
        return 0xd31c54eFD3A4B5E6a993AaA4618D3700a12ff752;
    }

    function updateItem(
        MarketItem memory item,
        bool forSale,
        uint256 price
    ) public returns (bool) {
        require(
            item.tokenId == idToMarketItem[item.itemId].tokenId,
            "tokenId must match"
        );
        IERC721 nft = IERC721(idToMarketItem[item.itemId].nftContract);
        address seller = nft.ownerOf(idToMarketItem[item.itemId].tokenId);
        require(
            msg.sender == seller,
            "sender not proper seller"
        );
        
        require(price > 0, "Price must be at least 1 wei");
        idToMarketItem[item.itemId].price = price;
        idToMarketItem[item.itemId].forSale = forSale;
        idToMarketItem[item.itemId].seller = payable(seller);
        
        if (forSale == true){
            emit ListedNFT(idToMarketItem[item.itemId].nftContract, price, msg.sender, item.tokenId);
        }
        return true;
    }

    


    function _hash(NFTVoucher calldata voucher)
        internal
        view
        returns (bytes32)
    {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        keccak256(
                            "NFTVoucher(uint256 tokenId,uint256 minPrice,uint256 royalty,address token,bool isNative,string uri)"
                        ),
                        voucher.tokenId,
                        voucher.minPrice,
                        voucher.royalty,
                        voucher.token,
                        voucher.isNative,
                        keccak256(bytes(voucher.uri))
                    )
                )
            );
    }

    function getChainID() external view returns (uint256) {
        uint256 id;
        assembly {
            id := chainid()
        }
        return id;
    }

    function _verify(NFTVoucher calldata voucher)
        internal
        view
        returns (address)
    {
        bytes32 digest = _hash(voucher);
        return ECDSA.recover(digest, voucher.signature);
    }

    /* Places an item for sale on the marketplace */
    function createMarketItem(
        address payable nftOwner,
        address payable nftSeller,
        address nftContract,
        NFTVoucher calldata voucher
    ) internal returns (bool) {
        require(voucher.minPrice > 0, "Price must be at least 1 wei");
        // require(msg.value == listingPrice, "Price must be equal to listing price");
        _itemIds.increment();
        uint256 itemId = _itemIds.current();
        idToMarketItem[itemId] = MarketItem(
            itemId,
            nftContract,
            voucher.tokenId,
            nftSeller,
            nftOwner,
            voucher.minPrice,
            false,
            voucher.royalty,
            voucher.token,
            voucher.isNative,
            true
        );

        emit ListedNFT(nftContract, voucher.minPrice, nftOwner, voucher.tokenId);

        return true;
    }

    function mintNFT(
        NFTVoucher calldata voucher,
        address nftContract
    ) public returns (bool) {

        require(voucher.minPrice > 0, "Price must be at least 1 wei");

        IERC721Merchant nft = IERC721Merchant(nftContract);

        nft.mint(msg.sender, voucher.tokenId, voucher.uri);

        bool created = createMarketItem(payable(msg.sender), payable(msg.sender), nftContract, voucher);
        if (created){
            uint256 itemId = _itemIds.current();
            idToMarketItem[itemId].forSale = true;
        }
        return created;
    }

    function fetchMarketItems(address contractAddress) public view returns (MarketItem[] memory) {
        uint256 itemCount = _itemIds.current();
        uint256 currentIndex = 0;

        MarketItem[] memory items = new MarketItem[](itemCount);
        for (uint256 i = 0; i < itemCount; i++) {
            if (idToMarketItem[i + 1].nftContract == contractAddress) {
            uint256 currentId = i + 1;
            MarketItem storage currentItem = idToMarketItem[currentId];
            items[currentIndex] = currentItem;
            currentIndex += 1;
            }
        }
        return items;
    }
}



// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity >=0.7.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";

import "hardhat/console.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

pragma abicoder v2;

contract ERC721FancyMerchant is
    ReentrancyGuard,
    ERC721URIStorage,
    EIP712,
    AccessControl,
    Ownable
{
    using Counters for Counters.Counter;
    using SafeMath for uint256;
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bool publicContract = false;
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
        bool indexed listed,
        uint256 indexed price,
        address indexed from,
        uint256 indexed tokenId
    ) anonymous;

    mapping(uint256 => MarketItem) private idToMarketItem;

    function mintAndTransferCustom(NFTVoucher calldata voucher)
        public
        nonReentrant
        returns (bool)
    {
        require(voucher.minPrice > 0, "Price must be at least 1 wei");
        address signer = redeem(msg.sender, voucher.minPrice, voucher);
        return createMarketItem(payable(signer), payable(msg.sender), voucher);
    }

    function createSaleCustom(MarketItem memory item) public nonReentrant returns (bool) {
        require(item.price > 0, "Price must be at least 1 wei");
        require(
            item.price == idToMarketItem[item.itemId].price,
            "Price must match"
        );
        MarketItem storage currentItem = idToMarketItem[item.itemId];
        require(currentItem.forSale == true, "Not for sale");
        address walletAddress = getThredAddress();
        address seller = ownerOf(currentItem.tokenId);
        address payable owner = currentItem.owner;
        address tokenContract = currentItem.tokenContract;
        uint256 price = currentItem.price;
        uint256 royalty = currentItem.royalty;
        uint256 fee = calculateFee(price, 3);
        uint256 royalties = calculateFee(price, royalty);
        uint256 calculated = calculateFee(price, 97 - royalty);
        IERC20 paymentToken = IERC20(tokenContract);
        require(
            paymentToken.allowance(msg.sender, address(this)) >= price,
            "Insufficient Allowance"
        );
        require(
            paymentToken.transferFrom(msg.sender, seller, calculated),
            "transfer Failed"
        );
        require(
            paymentToken.transferFrom(msg.sender, owner, royalties),
            "transfer Failed"
        );
        require(
            paymentToken.transferFrom(msg.sender, walletAddress, fee),
            "transfer Failed"
        );
        emit Sale(price, seller, msg.sender, currentItem.tokenId);
        _transfer(seller, msg.sender, currentItem.tokenId);
        idToMarketItem[item.itemId].seller = payable(msg.sender);
        idToMarketItem[item.itemId].forSale = false;
        return true;
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
        string memory tknName,
        string memory tknSymbol,
        string memory domain,
        string memory version,
        address minter
    ) ERC721(tknName, tknSymbol) EIP712(domain, version) {
        if (minter != address(0)) {
            _setupRole(MINTER_ROLE, minter);
        } else {
            publicContract = true;
        }
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
        address seller = ownerOf(idToMarketItem[item.itemId].tokenId);
        require(
            msg.sender == seller,
            "sender not proper seller"
        );
        
        require(price > 0, "Price must be at least 1 wei");
        idToMarketItem[item.itemId].price = price;
        idToMarketItem[item.itemId].forSale = forSale;
        idToMarketItem[item.itemId].seller = payable(seller);
        
        if (forSale == true){
          emit ListedNFT(true, price, msg.sender, item.tokenId);
        }
        return true;
    }

    function redeem(
        address redeemer,
        uint256 price,
        NFTVoucher calldata voucher
    ) internal returns (address) {
        require(voucher.minPrice > 0, "Price must be at least 1 wei");
        require(price >= voucher.minPrice, "Insufficient funds to redeem");
        address walletAddress = getThredAddress();
        address signer = _verify(voucher);
        if (!publicContract) {
            require(
                hasRole(MINTER_ROLE, signer),
                "Signature invalid or unauthorized"
            );
        }
        _mint(signer, voucher.tokenId);
        _setTokenURI(voucher.tokenId, voucher.uri);
        emit ListedNFT(true, price, signer, voucher.tokenId);
        uint256 calculated = calculateFee(voucher.minPrice, 97);
        uint256 fee = calculateFee(voucher.minPrice, 3);

        if (voucher.isNative || voucher.token == address(0)) {
            payable(signer).transfer(calculated);
            payable(walletAddress).transfer(fee);
        } else {
            IERC20 paymentToken = IERC20(voucher.token);
            if (
                paymentToken.allowance(redeemer, address(this)) >=
                voucher.minPrice
            ) {
                require(
                    paymentToken.transferFrom(redeemer, signer, calculated),
                    "transfer Failed"
                );
                require(
                    paymentToken.transferFrom(redeemer, walletAddress, fee),
                    "transfer Failed"
                );
            } else {
                revert("Insufficient Allowance");
            }
        }

        emit Sale(voucher.minPrice, signer, redeemer, voucher.tokenId);
        _transfer(signer, redeemer, voucher.tokenId);
        return signer;
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

    /* Places an item for sale on the marketplace */
    function createMarketItem(
        address payable nftOwner,
        address payable nftSeller,
        NFTVoucher calldata voucher
    ) public returns (bool) {
        require(voucher.minPrice > 0, "Price must be at least 1 wei");
        // require(msg.value == listingPrice, "Price must be equal to listing price");
        _itemIds.increment();
        uint256 itemId = _itemIds.current();
        idToMarketItem[itemId] = MarketItem(
            itemId,
            address(this),
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
        return true;
    }

    function mintNFT(
        NFTVoucher calldata voucher
    ) public returns (bool) {
        if (!publicContract) {
            require(
                hasRole(MINTER_ROLE, msg.sender),
                "invalid or unauthorized"
            );
        }
        require(voucher.minPrice > 0, "Price must be at least 1 wei");
        _mint(msg.sender, voucher.tokenId);
        _setTokenURI(voucher.tokenId, voucher.uri);
        bool created = createMarketItem(payable(msg.sender), payable(msg.sender), voucher);
        if (created){
            uint256 itemId = _itemIds.current();
            idToMarketItem[itemId].forSale = true;
            emit ListedNFT(true, voucher.minPrice, msg.sender, voucher.tokenId);
        }
        return true;
    }

    function fetchMarketItems() public view returns (MarketItem[] memory) {
        uint256 itemCount = _itemIds.current();
        uint256 currentIndex = 0;

        MarketItem[] memory items = new MarketItem[](itemCount);
        for (uint256 i = 0; i < itemCount; i++) {
            // if (idToMarketItem[i + 1].owner == address(0)) {
            uint256 currentId = i + 1;
            MarketItem storage currentItem = idToMarketItem[currentId];
            items[currentIndex] = currentItem;
            currentIndex += 1;
            // }
        }
        return items;
    }
}

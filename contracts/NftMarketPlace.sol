// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

error NftMarketPlace__PriceMustbeAboveZero();
error NftMarketPlace__NotApprovedForMarketPlace();
error NftMarketPlace__AlreadyListed(address nftAddress, uint256 tokenId);
error NftMarketPlace__NotOwner();
error NftMarketPlace__NotListed(address nftAddress, uint256 tokenId);
error NftMarketPlace__PriceNotMet(address nftAddress, uint256 tokenId, uint256 price);
error NftMarketPlace__ReentrancyAttack();
error NftMarketPlace__NoProceeds();
error NftMarketPlace__TransferFailed();

contract NftMarketPlace {
    struct Listing {
        uint256 price;
        address seller;
    }

    event ItemListed(
        address indexed seller,
        address indexed nftAddress,
        uint256 indexed tokenId,
        uint256 price
    );

    event ItemBought(
        address indexed buyer,
        address indexed nftAddress,
        uint256 indexed tokenId,
        uint256 price
    );

    event ItemCanceled(
        address indexed seller,
        address indexed nftAddress,
        uint256 indexed tokenId
    );

    //NFT contract address->nft tokenId -> listing
    mapping(address => mapping(uint256 => Listing)) private s_listings;
    //Seller address => amount earned
    mapping(address => uint256) private s_proceeds;
    //Reentrancy lock
    bool private lock;

    /////////////////////////
    //////Modifier Function//
    /////////////////////////
    modifier notListed(
        address nftAddress,
        uint256 tokenId,
        address owner
    ) {
        Listing memory listing = s_listings[nftAddress][tokenId];
        if (listing.price > 0) {
            revert NftMarketPlace__AlreadyListed(nftAddress, tokenId);
        }
        _;
    }

    modifier isOwner(
        address nftAddress,
        uint256 tokenId,
        address spender
    ) {
        IERC721 nft = IERC721(nftAddress);
        address owner = nft.ownerOf(tokenId);
        if (spender != owner) {
            revert NftMarketPlace__NotOwner();
        }
        _;
    }
    modifier isListed(address nftAddress, uint256 tokenId) {
        Listing memory listing = s_listings[nftAddress][tokenId];
        if (listing.price <= 0) {
            revert NftMarketPlace__NotListed(nftAddress, tokenId);
        }
        _;
    }

    /////////////////////////
    //////Main Function//////
    /////////////////////////

    /* @notice Method for listing your Nft on the marketplace
     * @params nftAddress: Address of the NFt
     * @params tokenId: TokenId of the NFt
     * @params price: Price of the NFt
     * @dev Technically, we could have contract be the escrow for the nft nut this
     * way people can still hold their NFT when listed
     */

    function listItem(
        address nftAddress,
        uint256 tokenId,
        uint256 price
    )
        external
        //Challenge use chainlink to accept payment in a subset of tokens
        notListed(nftAddress, tokenId, msg.sender)
        isOwner(nftAddress, tokenId, msg.sender)
    {
        if (price <= 0) {
            revert NftMarketPlace__PriceMustbeAboveZero();
        }
        //1. Send the NFT to contract. Transfer (expensive)
        //2. Owners can still hold their NFTs and give marketplace to sell it
        IERC721 nft = IERC721(nftAddress);
        if (nft.getApproved(tokenId) != address(this)) {
            revert NftMarketPlace__NotApprovedForMarketPlace();
        }
        s_listings[nftAddress][tokenId] = Listing(price, msg.sender);
        emit ItemListed(msg.sender, nftAddress, tokenId, price);
    }

    function buyItem(
        address nftAddress,
        uint256 tokenId
    ) external payable isListed(nftAddress, tokenId) {
        Listing memory listedItem = s_listings[nftAddress][tokenId];
        if (msg.value < listedItem.price) {
            revert NftMarketPlace__PriceNotMet(nftAddress, tokenId, listedItem.price);
        }
        lock = true;
        if (!lock) {
            revert NftMarketPlace__ReentrancyAttack();
        }
        IERC721(nftAddress).safeTransferFrom(listedItem.seller, msg.sender, tokenId);
        // We don't just send sellet the money...
        //// https://fravoll.github.io/solidity-patterns/pull_over_push.html
        //
        //Sending money to the user ❌
        //Have them withdraw the money ✅

        s_proceeds[listedItem.seller] += msg.value;
        delete (s_listings[nftAddress][tokenId]);

        //check to make sure NFT was transffered
        emit ItemBought(msg.sender, nftAddress, tokenId, listedItem.price);
        lock = false;
    }

    function cancelListing(
        address nftAddress,
        uint256 tokenId
    ) external isOwner(nftAddress, tokenId, msg.sender) isListed(nftAddress, tokenId) {
        delete (s_listings[nftAddress][tokenId]);
        emit ItemCanceled(msg.sender, nftAddress, tokenId);
    }

    function updateListing(
        address nftAddress,
        uint256 tokenId,
        uint256 newPrice
    ) external isListed(nftAddress, tokenId) isOwner(nftAddress, tokenId, msg.sender) {
        // We should check the value of `newPrice` and revert if it's below zero (like we also check in `listItem()`)
        if (newPrice <= 0) {
            revert NftMarketPlace__PriceMustbeAboveZero();
        }
        // lock = true;
        // if (!lock) {
        //     revert NftMarketPlace__ReentrancyAttack();
        // }
        s_listings[nftAddress][tokenId].price = newPrice;
        emit ItemListed(msg.sender, nftAddress, tokenId, newPrice);
        // lock = false;
    }

    function withdrawProceeds() external {
        uint256 proceeds = s_proceeds[msg.sender];
        if (proceeds <= 0) {
            revert NftMarketPlace__NoProceeds();
        }

        s_proceeds[msg.sender] = 0;
        (bool success, ) = payable(msg.sender).call{value: proceeds}("");
        if (!success) {
            revert NftMarketPlace__TransferFailed();
        }
    }

    ////////////////////////////
    ////Getter Functions///////
    ///////////////////////////

    function getListing(
        address nftAddress,
        uint256 tokenId
    ) external view returns (Listing memory) {
        return s_listings[nftAddress][tokenId];
    }

    function getProceeds(address seller) external view returns (uint256) {
        return s_proceeds[seller];
    }
}

// 1. list item -> list the NFT to marketPLace
//2. buyItem-> buy the Nfts
//3. cancelItem-> cancel a listing
//4. updateListing-> Update price
//5. withdrawProceed-> withhdraw payment for my bought NFTs

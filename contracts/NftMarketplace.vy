# SPDX-License-Identifier: MIT
# @version ^0.3.7

from vyper.interfaces import ERC721

# @title NftMarketplace
# @author jrmunchkin
# @notice This contract creates a NFT marketplace where any Nft collection can be listed or bought
# Every user can withdraw the ETH from their sold NFT.

struct Listing:
    price: uint256
    seller: address

s_listings: HashMap[address, HashMap[uint256, Listing]]
s_proceeds: HashMap[address, uint256]

event NftListed:
    seller: indexed(address)
    nftAddress: indexed(address)
    tokenId: indexed(uint256)
    price: uint256

event NftBought:
    buyer: indexed(address)
    nftAddress: indexed(address)
    tokenId: indexed(uint256)
    price: uint256

event NftCanceled:
    seller: indexed(address)
    nftAddress: indexed(address)
    tokenId: indexed(uint256)

event ProceedsWithdraw:
    seller: indexed(address)
    amount: uint256

@external
def listNft(_nftAddress: address, _tokenId: uint256, _price: uint256):
    """
    @notice Allow user to list any NFT thanks to the NFT contract address and the token id
    @param _nftAddress Address of the NFT collection
    @param _tokenId Token id of the NFT item
    @param _price Price the user wish to sell his NFT
    @dev emit an event NftListed when the NFT has been listed
    Check that the NFT has not been already listed
    Check that the NFT belongs to the user
    """
    listing: Listing = self.s_listings[_nftAddress][_tokenId]
    assert listing.price <= 0, "Nft already listed"
    owner: address = ERC721(_nftAddress).ownerOf(_tokenId)
    assert owner == msg.sender, "Not owner"
    assert _price > 0, "Price must be above 0"
    assert ERC721(_nftAddress).getApproved(_tokenId) == self, "Not approved for marketplace"
    self.s_listings[_nftAddress][_tokenId] = Listing({price: _price, seller: msg.sender})
    log NftListed(msg.sender, _nftAddress, _tokenId, _price)

@external
@payable
def buyNft(_nftAddress: address, _tokenId: uint256):
    """
    @notice Allow user to buy any NFT thanks to the NFT contract address and the token id
    @param _nftAddress Address of the NFT collection
    @param _tokenId Token id of the NFT item
    @dev emit an event NftBought when the NFT has been bought
    Check that the NFT has already been listed
    """
    listing: Listing = self.s_listings[_nftAddress][_tokenId]
    assert listing.price > 0, "Nft not listed"
    assert msg.value >= listing.price, "Price not met"
    self.s_proceeds[listing.seller] += msg.value
    self.s_listings[_nftAddress][_tokenId] = Listing({price: 0, seller: empty(address)})
    ERC721(_nftAddress).safeTransferFrom(listing.seller, msg.sender, _tokenId, b"")
    log NftBought(msg.sender, _nftAddress, _tokenId, listing.price)

@external
def cancelNftListing(_nftAddress: address, _tokenId: uint256):
    """
    @notice Allow user to cancel listing of any NFT thanks to the NFT contract address and the token id
    @param _nftAddress Address of the NFT collection
    @param _tokenId Token id of the NFT item
    @dev emit an event NftCanceled when the NFT has been canceled
    Check that the NFT belongs to the user
    Check that the NFT has already been listed
    """
    owner: address = ERC721(_nftAddress).ownerOf(_tokenId)
    assert owner == msg.sender, "Not owner"
    listing: Listing = self.s_listings[_nftAddress][_tokenId]
    assert listing.price > 0, "Nft not listed"
    self.s_listings[_nftAddress][_tokenId] = Listing({price: 0, seller: empty(address)})
    log NftCanceled(msg.sender, _nftAddress, _tokenId)

@external
def updateNftListing(_nftAddress: address, _tokenId: uint256, _newPrice: uint256):
    """
    @notice Allow user to update listing of any NFT thanks to the NFT contract address and the token id
    @param _nftAddress Address of the NFT collection
    @param _tokenId Token id of the NFT item
    @param _newPrice New price the user wish to sell his NFT
    @dev emit an event NftListed when the NFT has been listed
    Check that the NFT belongs to the user
    Check that the NFT has already been listed
    """
    owner: address = ERC721(_nftAddress).ownerOf(_tokenId)
    assert owner == msg.sender, "Not owner"
    listing: Listing = self.s_listings[_nftAddress][_tokenId]
    assert listing.price > 0, "Nft not listed"
    assert _newPrice > 0, "Price must be above 0"
    self.s_listings[_nftAddress][_tokenId].price = _newPrice
    log NftListed(msg.sender, _nftAddress, _tokenId, _newPrice)

@external
def withdrawProceeds():
    """
    @notice Allow user to withdraw all the ETH of his sold NFT
    @dev emit an event proceedsWithdraw when the ETH have been withdraw
    """
    proceeds: uint256 = self.s_proceeds[msg.sender]
    assert proceeds > 0, "No proceeds"
    self.s_proceeds[msg.sender] = 0
    send(msg.sender, proceeds)
    log ProceedsWithdraw(msg.sender, proceeds)

@external
@view
def getListing(_nftAddress: address, _tokenId: uint256) -> Listing:
    """
    @notice Get the listing of any NFT thanks to the NFT contract address and the token id
    @param _nftAddress Address of the NFT collection
    @param _tokenId Token id of the NFT item
    @return listing Listing of the NFT
    """
    return self.s_listings[_nftAddress][_tokenId]

@external
@view
def getProceeds(_seller: address) -> uint256:
    """
    @notice Get the amount of proceeds of a specific user
    @param _seller Address of the user
    @return amount Amount to proceed
    """
    return self.s_proceeds[_seller]
            
# SPDX-License-Identifier: MIT
# @version ^0.3.7

import interfaces.VRFCoordinatorV2Interface as VRFCoordinatorV2Interface

from vyper.interfaces import ERC721

implements: ERC721

interface ERC721Receiver:
    def onERC721Received(
        _operator: address,
        _from: address,
        _tokenId: uint256,
        _data: Bytes[1024]
) -> bytes4: nonpayable

# @title IsaacNft
# @author jrmunchkin
# @notice This contract creates a NFT collection on the theme of The binding of Isaac.
# Isaac characters are sort regarding the rarity from Legendary to Common. The chance to get a character or another is based on randomness + the percentage of the rarity.
# The contract allow each user to mint a maximum of 3 NFTs.
# @dev The constructor takes a mint fee in ETH and an array of token uris for each characters.
# This contract implements Chainlink VRF to pick a random rarity and character.

enum Legendary:
    THELOST

enum Rare:
    ISAAC
    AZAZEL
    QUESTION

enum Common:
    MAGDALENE
    CAIN
    JUDAS
    EVE
    SAMSO
    EDEN
    LAZARUS


######
# STATE VARIABLE OF ERC721 INTERFACE
######

# @dev ERC165 interface ID of ERC165
ERC165_INTERFACE_ID: constant(bytes32) = 0x0000000000000000000000000000000000000000000000000000000001ffc9a7

# @dev ERC165 interface ID of ERC721
ERC721_INTERFACE_ID: constant(bytes32) = 0x0000000000000000000000000000000000000000000000000000000080ac58cd

# @dev Mapping from NFT ID to the address that owns it.
idToOwner: HashMap[uint256, address]

# @dev Mapping from NFT ID to approved address.
idToApprovals: HashMap[uint256, address]

# @dev Mapping from owner address to count of his tokens.
ownerToNFTokenCount: HashMap[address, uint256]

# @dev Mapping from owner address to mapping of operator addresses.
ownerToOperators: HashMap[address, HashMap[address, bool]]

#@dev Maping from NFT ID to token URI
idToURI: HashMap[uint256, String[64]]

# @dev Address of minter, who can mint a token
minter: address

# @dev Name of the collection
name: public(String[64])

# @dev Symbol of the collection
symbol: public(String[3])

# @dev Mapping of interface id to bool about whether or not it's supported
supportedInterfaces: HashMap[bytes32, bool]

######
# STATE VARIABLE SPECIFICS TO THE CONTRACT
######

REQUEST_CONFIRMATIONS: constant(uint16) = 3
NUM_WORDS: constant(uint32) = 1
MAX_CHANCE_VALUE: constant(uint256) = 100
NB_RARITY: constant(uint256) = 3

i_vrfCoordinator: immutable(VRFCoordinatorV2Interface)
i_subscriptionId: immutable(uint64)
i_gasLane: immutable(bytes32)
i_callbackGasLimit: immutable(uint32)
s_tokenCounter: uint256
s_isaacTokenUris: DynArray[DynArray[String[64], 100], NB_RARITY]
s_mintFee: uint256
s_requestIdToSender: HashMap[uint256, address]
s_userFreeNft: HashMap[address, uint256]

######
# EVENTS OF ERC721 INTERFACE
######

event Transfer:
    sender: indexed(address)
    receiver: indexed(address)
    tokenId: indexed(uint256)

event Approval:
    owner: indexed(address)
    approved: indexed(address)
    tokenId: indexed(uint256)

event ApprovalForAll:
    owner: indexed(address)
    operator: indexed(address)
    approved: bool

######
# EVENTS SPECIFICS TO THE CONTRACT
######

event NftRequested:
    requestId: indexed(uint256)
    requester: address

event NftMinted:
    rarity: uint256
    character: uint256
    minter: indexed(address)

######
# CONSTRUCTOR
######

@external
def __init__(
    _vrfCoordinatorV2: address,
    _subscriptionId: uint64,
    _gasLane: bytes32,
    _callbackGasLimit: uint32,
    _isaacTokenUris: DynArray[DynArray[String[64], 100], NB_RARITY],
    _mintFee: uint256
    ):
    """
    @notice contructor
    @param _vrfCoordinatorV2 VRF Coordinator contract address
    @param _subscriptionId Subscription Id of Chainlink VRF
    @param _gasLane Gas lane of Chainlink VRF
    @param _callbackGasLimit Callback gas limit of Chainlink VRF
    @param _isaacTokenUris Array of the token uris of each characters
    @param _mintFee Fee vato mint an NFT in ETH
    """
    self.supportedInterfaces[ERC165_INTERFACE_ID] = True
    self.supportedInterfaces[ERC721_INTERFACE_ID] = True
    self.minter = msg.sender
    self.name = "Isaac"
    self.symbol = "ISC"
    i_vrfCoordinator = VRFCoordinatorV2Interface(_vrfCoordinatorV2)
    i_subscriptionId = _subscriptionId
    i_gasLane = _gasLane
    i_callbackGasLimit = _callbackGasLimit
    self.s_tokenCounter = 0
    self.s_isaacTokenUris = _isaacTokenUris
    self.s_mintFee = _mintFee

######
# FUNCTIONS OF ERC721 INTERFACE
######

@external
@view
def supportsInterface(_interfaceID: bytes32) -> bool:
    """
    @param _interfaceID Id of the interface
    @dev Interface identification is specified in ERC-165.
    """
    return self.supportedInterfaces[_interfaceID]

@external
@view
def balanceOf(_owner: address) -> uint256:
    """
    @param _owner Address for whom to query the balance.
    @dev Returns the number of NFTs owned by `_owner`.
    Throws if `_owner` is the zero address. NFTs assigned to the zero address are considered invalid.
    """
    assert _owner != empty(address)
    return self.ownerToNFTokenCount[_owner]

@external
@view
def ownerOf(_tokenId: uint256) -> address:
    """
    @param _tokenId The identifier for an NFT.
    @dev Returns the address of the owner of the NFT.
    Throws if `_tokenId` is not a valid NFT.
    """
    owner: address = self.idToOwner[_tokenId]
    # Throws if `_tokenId` is not a valid NFT
    assert owner != empty(address)
    return owner

@external
@view
def getApproved(_tokenId: uint256) -> address:
    """
    @param _tokenId ID of the NFT to query the approval of.
    @dev Get the approved address for a single NFT.
    Throws if `_tokenId` is not a valid NFT.
    """
    # Throws if `_tokenId` is not a valid NFT
    assert self.idToOwner[_tokenId] != empty(address)
    return self.idToApprovals[_tokenId]

@external
@view
def isApprovedForAll(_owner: address, _operator: address) -> bool:
    """
    @param _owner The address that owns the NFTs.
    @param _operator The address that acts on behalf of the owner.
    @dev Checks if `_operator` is an approved operator for `_owner`.
    """
    return (self.ownerToOperators[_owner])[_operator]

@external
@view
def tokenURI(_tokenId: uint256) -> String[64]:
    """
    @param _tokenId The token id
    @return tokenURI The token URI
    """
    return self.idToURI[_tokenId]

@internal
@view
def _isApprovedOrOwner(_spender: address, _tokenId: uint256) -> bool:
    """
    @param spender address of the spender to query
    @param tokenId uint256 ID of the token to be transferred
    @return bool whether the msg.sender is approved for the given token ID,
    is an operator of the owner, or is the owner of the token
    @dev Returns whether the given spender can transfer a given token ID
    """
    owner: address = self.idToOwner[_tokenId]
    spenderIsOwner: bool = owner == _spender
    spenderIsApproved: bool = _spender == self.idToApprovals[_tokenId]
    spenderIsApprovedForAll: bool = (self.ownerToOperators[owner])[_spender]
    return (spenderIsOwner or spenderIsApproved) or spenderIsApprovedForAll

@internal
def _addTokenTo(_to: address, _tokenId: uint256):
    """
    @dev Add a NFT to a given address
    Throws if `_tokenId` is owned by someone.
    """
    # Throws if `_tokenId` is owned by someone
    assert self.idToOwner[_tokenId] == empty(address)
    # Change the owner
    self.idToOwner[_tokenId] = _to
    # Change count tracking
    self.ownerToNFTokenCount[_to] += 1

@internal
def _removeTokenFrom(_from: address, _tokenId: uint256):
    """
    @dev Remove a NFT from a given address
    Throws if `_from` is not the current owner.
    """
    # Throws if `_from` is not the current owner
    assert self.idToOwner[_tokenId] == _from
    # Change the owner
    self.idToOwner[_tokenId] = empty(address)
    # Change count tracking
    self.ownerToNFTokenCount[_from] -= 1

@internal
def _clearApproval(_owner: address, _tokenId: uint256):
    """
    @dev Clear an approval of a given address
    Throws if `_owner` is not the current owner
    """
    # Throws if `_owner` is not the current owner
    assert self.idToOwner[_tokenId] == _owner
    if self.idToApprovals[_tokenId] != empty(address):
        # Reset approvals
        self.idToApprovals[_tokenId] = empty(address)

@internal
def _transferFrom(_from: address, _to: address, _tokenId: uint256, _sender: address):
    """
    @dev Execute transfer of a NFT.
    Throws unless `msg.sender` is the current owner, an authorized operator, or the approved
    address for this NFT. (NOTE: `msg.sender` not allowed in private function so pass `_sender`.)
    Throws if `_to` is the zero address.
    Throws if `_from` is not the current owner.
    Throws if `_tokenId` is not a valid NFT.
    """
    # Check requirements
    assert self._isApprovedOrOwner(_sender, _tokenId)
    # Throws if `_to` is the zero address
    assert _to != empty(address)
    # Clear approval. Throws if `_from` is not the current owner
    self._clearApproval(_from, _tokenId)
    # Remove NFT. Throws if `_tokenId` is not a valid NFT
    self._removeTokenFrom(_from, _tokenId)
    # Add NF
    self._addTokenTo(_to, _tokenId)
    # Log the transfer
    log Transfer(_from, _to, _tokenId)

@internal
def _setTokenURI(_tokenId: uint256, _tokenURI: String[64]):
    """
    @dev Set the URI for a token
    Throws if the token ID does not exist
    """
    assert self.idToOwner[_tokenId] != empty(address)
    self.idToURI[_tokenId] = _tokenURI

@internal
def _safeMint(_to: address, _tokenId: uint256) -> bool:
    """
    @param _to The address that will receive the minted tokens.
    @param _tokenId The token id to mint.
    @return A boolean that indicates if the operation was successful.
    @dev Function to mint tokens
    Throws if `_to` is zero address.
    Throws if `_tokenId` is owned by someone.
    """
    # Throws if `_to` is zero address
    assert _to != empty(address)
    # Add NFT. Throws if `_tokenId` is owned by someone
    self._addTokenTo(_to, _tokenId)
    log Transfer(empty(address), _to, _tokenId)
    return True

@external
def transferFrom(_from: address, _to: address, _tokenId: uint256):
    """
    @notice The caller is responsible to confirm that `_to` is capable of receiving NFTs or else
    they maybe be permanently lost.
    @param _from The current owner of the NFT.
    @param _to The new owner.
    @param _tokenId The NFT to transfer.
    @dev Throws unless `msg.sender` is the current owner, an authorized operator, or the approved
    address for this NFT
    Throws if `_from` is not the current owner.
    Throws if `_to` is the zero address.
    Throws if `_tokenId` is not a valid NFT.
    """
    self._transferFrom(_from, _to, _tokenId, msg.sender)

@external
def safeTransferFrom(
        _from: address,
        _to: address,
        _tokenId: uint256,
        _data: Bytes[1024]=b""
    ):
    """
    @param _from The current owner of the NFT.
    @param _to The new owner.
    @param _tokenId The NFT to transfer
    @param _data Additional data with no specified format, sent in call to `_to`
    @dev Transfers the ownership of an NFT from one address to another address
    Throws unless `msg.sender` is the current owner, an authorized operator, or the
    approved address for this NFT.
    Throws if `_from` is not the current owner.
    Throws if `_to` is the zero address
    Throws if `_tokenId` is not a valid NFT.
    If `_to` is a smart contract, it calls `onERC721Received` on `_to` and throws if
    the return value is not `bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"))`
    """
    self._transferFrom(_from, _to, _tokenId, msg.sender)
    if _to.is_contract: # check if `_to` is a contract address
        returnValue: bytes4 = ERC721Receiver(_to).onERC721Received(msg.sender, _from, _tokenId, _data)
        # Throws if transfer destination is a contract which does not implement 'onERC721Received'
        assert returnValue == method_id("onERC721Received(address,address,uint256,bytes)", output_type=bytes4)

@external
def approve(_approved: address, _tokenId: uint256):
    """
    @param _approved Address to be approved for the given NFT ID.
    @param _tokenId ID of the token to be approved.
    @dev Set or reaffirm the approved address for an NFT. The zero address indicates there is no approved address.
    Throws unless `msg.sender` is the current NFT owner, or an authorized operator of the current owner.
    Throws if `_tokenId` is not a valid NFT. (NOTE: This is not written the EIP)
    Throws if `_approved` is the current owner. (NOTE: This is not written the EIP)
    """
    owner: address = self.idToOwner[_tokenId]
    # Throws if `_tokenId` is not a valid NFT
    assert owner != empty(address)
    # Throws if `_approved` is the current owner
    assert _approved != owner
    # Check requirements
    senderIsOwner: bool = self.idToOwner[_tokenId] == msg.sender
    senderIsApprovedForAll: bool = (self.ownerToOperators[owner])[msg.sender]
    assert (senderIsOwner or senderIsApprovedForAll)
    # Set the approval
    self.idToApprovals[_tokenId] = _approved
    log Approval(owner, _approved, _tokenId)

@external
def setApprovalForAll(_operator: address, _approved: bool):
    """
    @notice This works even if sender doesn't own any tokens at the time.
    @param _operator Address to add to the set of authorized operators.
    @param _approved True if the operators is approved, false to revoke approval.
    @dev Enables or disables approval for a third party ("operator") to manage all of
    `msg.sender`'s assets. It also emits the ApprovalForAll event.
    Throws if `_operator` is the `msg.sender`. (NOTE: This is not written the EIP)
    """
    # Throws if `_operator` is the `msg.sender`
    assert _operator != msg.sender
    self.ownerToOperators[msg.sender][_operator] = _approved
    log ApprovalForAll(msg.sender, _operator, _approved)

@external
def mint(_to: address, _tokenId: uint256) -> bool:
    """
    @param _to The address that will receive the minted tokens.
    @param _tokenId The token id to mint.
    @return A boolean that indicates if the operation was successful.
    @dev Function to mint tokens
    Throws if `msg.sender` is not the minter.
    """
    # Throws if `msg.sender` is not the minter
    assert msg.sender == self.minter
    return self._safeMint(_to, _tokenId)

@external
def burn(_tokenId: uint256):
    """
    @param _tokenId uint256 id of the ERC721 token to be burned.
    @dev Burns a specific ERC721 token.
    Throws unless `msg.sender` is the current owner, an authorized operator, or the approved
    address for this NFT.
    Throws if `_tokenId` is not a valid NFT
    """
    # Check requirements
    assert self._isApprovedOrOwner(msg.sender, _tokenId)
    owner: address = self.idToOwner[_tokenId]
    # Throws if `_tokenId` is not a valid NFT
    assert owner != empty(address)
    self._clearApproval(owner, _tokenId)
    self._removeTokenFrom(owner, _tokenId)
    log Transfer(owner, empty(address), _tokenId)

######
# FUNCTIONS SPECIFICS TO THE CONTRACT
######

@external
def mintFreeNft():
    """
    @notice Allow user to mint a free NFT without the mint fees (limit of 3 by user)
    """
    assert self.s_userFreeNft[msg.sender] < 3, "No more Free Nfts"
    self.requestNft()
    self.s_userFreeNft[msg.sender] += 1

@external
@payable
def mintNft():
    """
    @notice Allow user to mint an NFT by paying the mint fees
    """
    assert msg.value >= self.s_mintFee, "Not enough ETH"
    self.requestNft()

@internal
def requestNft():
    """
    @notice Send a request to the chainlink VRF to get a random number to decide wich NFT the user will get.
    @dev Call Chainlink VRF to request a random NFT
    emit an event NftRequested when request NFT is called
    """
    requestId: uint256 = i_vrfCoordinator.requestRandomWords(i_gasLane, i_subscriptionId, REQUEST_CONFIRMATIONS, i_callbackGasLimit, NUM_WORDS)
    self.s_requestIdToSender[requestId] = msg.sender
    log NftRequested(requestId, msg.sender)

@internal
def fulfillRandomWords(_requestId: uint256, _randomWords: DynArray[uint256, NUM_WORDS]):
    """
    @notice Picked a random NFT
    @dev Call by the Chainlink VRF after requesting a random NFT
    emit an event NftMinted when random NFT has been minted
    """
    requester: address = self.s_requestIdToSender[_requestId]
    newTokenId: uint256 = self.s_tokenCounter
    rarity: uint256 = 0
    character: uint256 = 0
    (rarity, character) = self.getRandomCharacterInternal(_randomWords[0])
    self.s_tokenCounter += 1
    self._safeMint(requester, newTokenId)
    self._setTokenURI(newTokenId, self.s_isaacTokenUris[rarity][character])
    log NftMinted(rarity, character, requester)

@external
def rawFulfillRandomWords(_requestId: uint256, _randomWords: DynArray[uint256, NUM_WORDS]):
    """
    @notice In solidity, this is the equivalent of inheriting the VRFConsumerBaseV2
    Vyper doesn't have inheritance, so we just add the function here
    """
    assert msg.sender == i_vrfCoordinator.address, "Only coordinator can fulfill!"
    self.fulfillRandomWords(_requestId, _randomWords)

@external
@view
def getRandomCharacter(_randomWord: uint256) -> (uint256, uint256):
    """
    @notice Get a random character by first determine the rarity
    @param _randomWord the random number to get the rarity and character
    @return rarity the rarity of the character
    @return character the character
    @dev For external call
    """
    return self.getRandomCharacterInternal(_randomWord)

@internal
@pure
def getRandomCharacterInternal(_randomWord: uint256) -> (uint256, uint256):
    """
    @notice Get a random character by first determine the rarity
    @param _randomWord the random number to get the rarity and character
    @return rarity the rarity of the character
    @return character the character
    """
    moddedRng: uint256 = _randomWord % MAX_CHANCE_VALUE
    cumulativeSum: uint256 = 0
    chanceArray: DynArray[uint256, NB_RARITY] = self.getChanceArray()
    for i in range(NB_RARITY):
        if moddedRng >= cumulativeSum and moddedRng < chanceArray[i]:
            return i, self.getRandomCharacterfromRarity(_randomWord, i)
        cumulativeSum = chanceArray[i]
    raise "Out of range"

@internal
@pure
def getRandomCharacterfromRarity(_randomWord: uint256, _indexRarity: uint256) -> uint256:
    """
    @notice Get a random character from teh rarity
    @param _randomWord the random number to get the rarity and character
    @param _indexRarity the rarity of the character
    @return character the character
    """
    if _indexRarity == 0:
        return _randomWord % 1
    if _indexRarity == 1:
        return _randomWord % 3
    if _indexRarity == 2:
        return _randomWord % 7
    raise "Out of range"

@internal
@pure
def getChanceArray() -> DynArray[uint256, NB_RARITY]:
    """
    @notice Get the chance array which help to determine the percentage of the rarity
    @return chanceArray the character
    """
    return [5, 40, MAX_CHANCE_VALUE]

@external
@view
def getMintFee() -> uint256:
    """
    @notice Get the mint fee to mint an NFT
    @return mintFee The mint fee
    """
    return self.s_mintFee

@external
@view
def getIsaacTokenUri(_rarity: uint256, _index: uint256) -> String[64]:
    """
    @notice Get the token uri thanks to the rarity and the index of the character
    @param _rarity The rarity of the character
    @param _index The index of the character
    @return tokenUris The token uri
    """
    return self.s_isaacTokenUris[_rarity][_index]

@external
@view
def getTokenCounter() -> uint256:
    """
    @notice Get the last token id
    @return tokenId The token id
    """
    return self.s_tokenCounter

@external
@view
def getNbUserFreeNft(_user: address) -> uint256:
    """
    @notice Get the number of free NFTs already minted for a specific user
    @param _user The user address
    @return nbFreeNft The number of free NFT already minted
    """
    return self.s_userFreeNft[_user]

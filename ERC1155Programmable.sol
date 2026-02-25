// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Burnable.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

/**
 * @title LuxuryX ERC1155 Programmable Token
 * @dev Hybrid production multi-token standard
 * Supports both fungible and non-fungible assets in one contract
 * 
 * Use Cases:
 * - Mixed Asset Portfolios
 * - Gaming Items (fungible currency + unique items)
 * - Loyalty Programs (points + rewards)
 * - Fractionalized Assets
 */
contract LuxuryXERC1155Programmable is 
    ERC1155, 
    ERC1155Burnable, 
    ERC1155Supply,
    ERC1155URIStorage,
    Ownable, 
    ReentrancyGuard, 
    Pausable, 
    Initializable 
{
    // ============ Structs ============
    
    struct TokenType {
        bool isFungible;
        uint256 maxSupply;
        uint256 mintPrice;
        bool onlyWhitelisted;
        bool transferable;
        uint16 royaltyBps;
        address royaltyRecipient;
    }
    
    // ============ State Variables ============
    
    string private _customName;
    string private _customSymbol;
    
    // Token configurations
    mapping(uint256 => TokenType) public tokenTypes;
    mapping(uint256 => mapping(address => bool)) public whitelisted;
    
    // Security Features
    mapping(address => bool) private _blacklisted;
    mapping(uint256 => uint256) private _totalMinted;
    
    // Track token IDs
    uint256[] private _tokenIds;
    
    // ============ Events ============
    
    event Initialized(
        address indexed owner,
        string name,
        string symbol,
        string baseURI
    );
    
    event TokenTypeCreated(
        uint256 indexed tokenId,
        bool isFungible,
        uint256 maxSupply,
        uint256 mintPrice,
        bool transferable
    );
    
    event TokensMinted(
        address indexed to,
        uint256 indexed tokenId,
        uint256 amount,
        string tokenURI
    );
    
    event WhitelistUpdated(
        uint256 indexed tokenId,
        address indexed account,
        bool isWhitelisted
    );
    
    event BlacklistUpdated(address indexed account, bool isBlacklisted);
    event RoyaltyUpdated(uint256 indexed tokenId, uint16 royaltyBps, address recipient);
    
    // ============ Constructor & Initializer ============
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() ERC1155("") Ownable(msg.sender) {
        _disableInitializers();
    }
    
    struct InitParams {
        address initialOwner;
        string name;
        string symbol;
        string baseURI;
    }
    
    function initialize(InitParams calldata params) external initializer {
        require(params.initialOwner != address(0), "Invalid owner");
        require(bytes(params.name).length > 0, "Name required");
        require(bytes(params.symbol).length > 0, "Symbol required");
        
        // Initialize ERC1155 - directly set URI
        _setURI(params.baseURI);
        
        _customName = params.name;
        _customSymbol = params.symbol;
        
        // Transfer ownership
        _transferOwnership(params.initialOwner);
        
        emit Initialized(params.initialOwner, params.name, params.symbol, params.baseURI);
    }
    
    // ============ Name/Symbol ============
    
    function name() external view returns (string memory) {
        return _customName;
    }
    
    function symbol() external view returns (string memory) {
        return _customSymbol;
    }
    
    // ============ Modifiers ============
    
    modifier notBlacklisted(address account) {
        require(!_blacklisted[account], "Account blacklisted");
        _;
    }
    
    modifier tokenExists(uint256 tokenId) {
        require(tokenTypes[tokenId].maxSupply > 0 || tokenId == 0, "Token type doesn't exist");
        _;
    }
    
    // ============ Token Type Management ============
    
    function createTokenType(
        uint256 tokenId,
        bool isFungible,
        uint256 maxSupply_,
        uint256 mintPrice_,
        bool onlyWhitelisted_,
        bool transferable_,
        uint16 royaltyBps_,
        address royaltyRecipient_,
        string memory tokenURI_
    ) external onlyOwner {
        require(tokenTypes[tokenId].maxSupply == 0, "Token ID already exists");
        require(maxSupply_ > 0, "Max supply must be > 0");
        require(royaltyBps_ <= 1500, "Royalty cannot exceed 15%");
        require(royaltyRecipient_ != address(0), "Invalid royalty recipient");
        
        tokenTypes[tokenId] = TokenType({
            isFungible: isFungible,
            maxSupply: maxSupply_,
            mintPrice: mintPrice_,
            onlyWhitelisted: onlyWhitelisted_,
            transferable: transferable_,
            royaltyBps: royaltyBps_,
            royaltyRecipient: royaltyRecipient_
        });
        
        _tokenIds.push(tokenId);
        
        if (bytes(tokenURI_).length > 0) {
            _setURI(tokenId, tokenURI_);
        }
        
        emit TokenTypeCreated(tokenId, isFungible, maxSupply_, mintPrice_, transferable_);
    }
    
    // ============ Minting Functions ============
    
    function mint(
        address to,
        uint256 tokenId,
        uint256 amount,
        string memory tokenURI_
    ) external payable onlyOwner nonReentrant notBlacklisted(to) tokenExists(tokenId) {
        require(to != address(0), "Invalid recipient");
        require(amount > 0, "Amount must be > 0");
        
        TokenType storage token = tokenTypes[tokenId];
        
        if (token.onlyWhitelisted) {
            require(whitelisted[tokenId][to], "Not whitelisted");
        }
        
        if (token.mintPrice > 0) {
            require(msg.value >= token.mintPrice * amount, "Insufficient payment");
        }
        
        require(_totalMinted[tokenId] + amount <= token.maxSupply, "Exceeds max supply");
        
        _mint(to, tokenId, amount, "");
        _totalMinted[tokenId] += amount;
        
        if (bytes(tokenURI_).length > 0) {
            _setURI(tokenId, tokenURI_);
        }
        
        emit TokensMinted(to, tokenId, amount, tokenURI_);
    }
    
    function mintBatch(
        address to,
        uint256[] memory tokenIds,
        uint256[] memory amounts,
        string[] memory tokenURIs
    ) external payable onlyOwner nonReentrant notBlacklisted(to) {
        require(to != address(0), "Invalid recipient");
        require(tokenIds.length == amounts.length, "Arrays length mismatch");
        require(tokenIds.length == tokenURIs.length, "URIs length mismatch");
        require(tokenIds.length > 0, "Empty array");
        require(tokenIds.length <= 20, "Too many tokens");
        
        uint256 totalValue = 0;
        
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            uint256 amount = amounts[i];
            
            require(amount > 0, "Amount must be > 0");
            require(tokenTypes[tokenId].maxSupply > 0, "Token doesn't exist");
            
            TokenType storage token = tokenTypes[tokenId];
            
            if (token.onlyWhitelisted) {
                require(whitelisted[tokenId][to], "Not whitelisted");
            }
            
            totalValue += token.mintPrice * amount;
            require(_totalMinted[tokenId] + amount <= token.maxSupply, "Exceeds max supply");
            
            if (bytes(tokenURIs[i]).length > 0) {
                _setURI(tokenId, tokenURIs[i]);
            }
            
            _totalMinted[tokenId] += amount;
        }
        
        if (totalValue > 0) {
            require(msg.value >= totalValue, "Insufficient payment");
        }
        
        _mintBatch(to, tokenIds, amounts, "");
        
        for (uint256 i = 0; i < tokenIds.length; i++) {
            emit TokensMinted(to, tokenIds[i], amounts[i], tokenURIs[i]);
        }
    }
    
    // ============ Transfer Overrides ============
    
    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) public override notBlacklisted(from) notBlacklisted(to) whenNotPaused {
        require(tokenTypes[id].transferable, "Token is non-transferable");
        super.safeTransferFrom(from, to, id, amount, data);
    }
    
    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) public override notBlacklisted(from) notBlacklisted(to) whenNotPaused {
        for (uint256 i = 0; i < ids.length; i++) {
            require(tokenTypes[ids[i]].transferable, "Token is non-transferable");
        }
        super.safeBatchTransferFrom(from, to, ids, amounts, data);
    }
    
    // ============ Whitelist Management ============
    
    function addToWhitelist(uint256 tokenId, address[] calldata accounts) external onlyOwner tokenExists(tokenId) {
        for (uint256 i = 0; i < accounts.length; i++) {
            require(accounts[i] != address(0), "Zero address");
            whitelisted[tokenId][accounts[i]] = true;
            emit WhitelistUpdated(tokenId, accounts[i], true);
        }
    }
    
    function removeFromWhitelist(uint256 tokenId, address[] calldata accounts) external onlyOwner tokenExists(tokenId) {
        for (uint256 i = 0; i < accounts.length; i++) {
            whitelisted[tokenId][accounts[i]] = false;
            emit WhitelistUpdated(tokenId, accounts[i], false);
        }
    }
    
    // ============ Blacklist Management ============
    
    function addToBlacklist(address account) external onlyOwner {
        require(account != address(0), "Zero address");
        require(account != owner(), "Cannot blacklist owner");
        require(!_blacklisted[account], "Already blacklisted");
        
        _blacklisted[account] = true;
        emit BlacklistUpdated(account, true);
    }
    
    function removeFromBlacklist(address account) external onlyOwner {
        require(_blacklisted[account], "Not blacklisted");
        
        _blacklisted[account] = false;
        emit BlacklistUpdated(account, false);
    }
    
    function isBlacklisted(address account) external view returns (bool) {
        return _blacklisted[account];
    }
    
    // ============ Royalty Management ============
    
    function updateRoyalty(
        uint256 tokenId,
        uint16 royaltyBps_,
        address royaltyRecipient_
    ) external onlyOwner tokenExists(tokenId) {
        require(royaltyBps_ <= 1500, "Royalty cannot exceed 15%");
        require(royaltyRecipient_ != address(0), "Invalid recipient");
        
        tokenTypes[tokenId].royaltyBps = royaltyBps_;
        tokenTypes[tokenId].royaltyRecipient = royaltyRecipient_;
        
        emit RoyaltyUpdated(tokenId, royaltyBps_, royaltyRecipient_);
    }
    
    function royaltyInfo(uint256 tokenId, uint256 salePrice) 
        external 
        view 
        returns (address receiver, uint256 royaltyAmount) 
    {
        receiver = tokenTypes[tokenId].royaltyRecipient;
        royaltyAmount = (salePrice * tokenTypes[tokenId].royaltyBps) / 10000;
    }
    
    // ============ Configuration ============
    
    function setTokenTransferable(uint256 tokenId, bool transferable) external onlyOwner tokenExists(tokenId) {
        tokenTypes[tokenId].transferable = transferable;
    }
    
    function setMintPrice(uint256 tokenId, uint256 newPrice) external onlyOwner tokenExists(tokenId) {
        tokenTypes[tokenId].mintPrice = newPrice;
    }
    
    function setWhitelistOnly(uint256 tokenId, bool enabled) external onlyOwner tokenExists(tokenId) {
        tokenTypes[tokenId].onlyWhitelisted = enabled;
    }
    
    function setTokenURI(uint256 tokenId, string memory tokenURI_) external onlyOwner tokenExists(tokenId) {
        _setURI(tokenId, tokenURI_);
    }
    
    // ============ Pausable ============
    
    function pause() external onlyOwner {
        _pause();
    }
    
    function unpause() external onlyOwner {
        _unpause();
    }
    
    // ============ View Functions ============
    
    function uri(uint256 tokenId) 
        public 
        view 
        override(ERC1155, ERC1155URIStorage) 
        returns (string memory) 
    {
        return super.uri(tokenId);
    }
    
    function totalSupply(uint256 tokenId) public view override(ERC1155Supply) returns (uint256) {
        return super.totalSupply(tokenId);
    }
    
    function getTokenIds() external view returns (uint256[] memory) {
        return _tokenIds;
    }
    
    function getTotalMinted(uint256 tokenId) external view returns (uint256) {
        return _totalMinted[tokenId];
    }
    
    function getRemainingSupply(uint256 tokenId) external view returns (uint256) {
        return tokenTypes[tokenId].maxSupply - _totalMinted[tokenId];
    }
    
    // ============ Required Overrides ============
    
    function _update(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values
    ) internal override(ERC1155, ERC1155Supply) whenNotPaused {
        super._update(from, to, ids, values);
    }
    
    /**
     * @dev See {IERC165-supportsInterface}
     * Only override ERC1155 since ERC1155URIStorage doesn't have supportsInterface
     */
    function supportsInterface(bytes4 interfaceId) 
        public 
        view 
        override(ERC1155) 
        returns (bool) 
    {
        return super.supportsInterface(interfaceId);
    }
    
    receive() external payable {
        revert("LuxuryXERC1155: ETH not accepted");
    }
}
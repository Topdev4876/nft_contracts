// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

contract WealthyApesERC721 is
    ERC721Upgradeable,
    ERC721EnumerableUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeMath for uint256;

    string public WEALTHYAPES_PROVENANCE; // IPFS URL WILL BE ADDED WHEN WEALTHYAPES ARE ALL SOLD OUT
    string public LICENSE_TEXT; // IT IS WHAT IT SAYS

    bool licenseLocked; // TEAM CAN'T EDIT THE LICENSE AFTER THIS GETS TRUE

    uint256 public maxWealthyApesPurchase;
    uint256 public MAX_WEALTHYAPES;
    uint256 public wealthyApesPrice; // each token price is 0.03 ETH

    address public royaltyReceiver;
    uint256 public royaltyPercent;
    uint256 public DENOMINATOR;

    bool public saleIsActive;

    mapping(uint256 => string) public wealthyApesNames;
    uint256 public wealthyApesReserve; // Reserve 125

    // baseURI
    string public baseURI;

    // FreeMint
    bytes32 merkleTreeRoot;
    uint256 public freeMintAmount;
    uint256 public maxFreeMintCnt;
    mapping(address => uint256) private claimFreeCnt;

    event WealthyApesNameChange(address _by, uint256 _tokenId, string _name);
    event LicenseisLocked(string _licenseText);

    function initialize(
        uint256 _MAX_WEALTHYAPES,
        uint256 _wealthyApesPrice,
        uint256 _DENOMINATOR,
        uint256 _wealthyApesReserve,
        address _royaltyReceiver,
        uint256 _royaltyPercent,
        uint256 _freeMintAmount
    ) public initializer {
        require(_royaltyPercent >= 100 && _royaltyPercent < 10000, "Invalid");
        __ERC721_init("Wealthy Apes Club", "WA");
        __Ownable_init();
        __ReentrancyGuard_init();

        WEALTHYAPES_PROVENANCE = "";
        LICENSE_TEXT = "";
        licenseLocked = false;
        saleIsActive = true;

        MAX_WEALTHYAPES = _MAX_WEALTHYAPES; // 10000
        wealthyApesPrice = _wealthyApesPrice; // 30000000000000000
        DENOMINATOR = _DENOMINATOR; // 10000
        wealthyApesReserve = _wealthyApesReserve; // 125

        freeMintAmount = _freeMintAmount; // 500

        royaltyReceiver = _royaltyReceiver;
        royaltyPercent = _royaltyPercent;
    }

    function reserveWealthyApes(address _to, uint256 _reserveAmount)
        external
        onlyOwner
    {
        require(
            _reserveAmount > 0 && _reserveAmount <= wealthyApesReserve,
            "Not enough reserve left for team"
        );
        wealthyApesReserve = wealthyApesReserve.sub(_reserveAmount);
        uint256 supply = totalSupply();
        for (uint256 i = 1; i <= _reserveAmount; i++) {
            _safeMint(_to, supply + i);
        }
    }

    function setProvenanceHash(string memory provenanceHash)
        external
        onlyOwner
    {
        WEALTHYAPES_PROVENANCE = provenanceHash;
    }

    function setBaseURI(string memory _newBaseURI) external onlyOwner {
        baseURI = _newBaseURI;
    }

    function changeRoyaltyReceiver(address _newReceiver) external onlyOwner {
        require(_newReceiver != address(0), "Invalid address");
        royaltyReceiver = _newReceiver;
    }

    function changeRoyaltyPercent(uint256 _newRoyalty) external onlyOwner {
        require(_newRoyalty >= 100 && _newRoyalty < 10000, "Invalid");
        royaltyPercent = _newRoyalty;
    }

    function flipSaleState() public onlyOwner {
        saleIsActive = !saleIsActive;
    }

    function tokensOfOwner(address _owner)
        external
        view
        returns (uint256[] memory)
    {
        uint256 tokenCount = balanceOf(_owner);
        if (tokenCount == 0) {
            // Return an empty array
            return new uint256[](0);
        } else {
            uint256[] memory result = new uint256[](tokenCount);
            uint256 index;
            for (index = 0; index < tokenCount; index++) {
                result[index] = tokenOfOwnerByIndex(_owner, index);
            }
            return result;
        }
    }

    // Returns the license for tokens
    function tokenLicense(uint256 _id) external view returns (string memory) {
        require(_id < totalSupply(), "CHOOSE A WEALTHYAPES WITHIN RANGE");
        return LICENSE_TEXT;
    }

    // Locks the license to prevent further changes
    function lockLicense() external onlyOwner {
        licenseLocked = true;
        emit LicenseisLocked(LICENSE_TEXT);
    }

    // Change the license
    function changeLicense(string memory _license) external onlyOwner {
        require(!licenseLocked, "License already locked");
        LICENSE_TEXT = _license;
    }

    function setMerkleTree(bytes32 _merkleTreeRoot) external onlyOwner {
        merkleTreeRoot = _merkleTreeRoot;
    }

    function mintNFT() external payable nonReentrant {
        require(saleIsActive, "Sale must be active to mint nft");
        require(
            totalSupply() < MAX_WEALTHYAPES,
            "Exceed max supply of WealthyApes"
        );
        uint256 freeMintableCnt = 0;
        uint256 mintedCnt = totalSupply().add(1);
        if (mintedCnt < freeMintAmount) {
            freeMintableCnt = freeMintAmount.sub(mintedCnt);
            if (freeMintableCnt > 3) freeMintableCnt = 3;
        }
        uint256 royaltyFee = wealthyApesPrice
            .mul(royaltyPercent)
            .mul(freeMintableCnt + 1)
            .div(DENOMINATOR);
        require(msg.value >= wealthyApesPrice.add(royaltyFee), "Invalid amount");

        uint256 restAmount = msg.value.sub(wealthyApesPrice).sub(royaltyFee);
        payable(msg.sender).transfer(restAmount);
        payable(royaltyReceiver).transfer(royaltyFee);
        payable(owner()).transfer(address(this).balance);

        for (uint256 i = 1; i <= freeMintableCnt + 1; i++)
            _safeMint(msg.sender, totalSupply().add(i));
    }

    function changeWealthyApesName(uint256 _tokenId, string memory _name)
        external
    {
        require(
            ownerOf(_tokenId) == msg.sender,
            "Hey, your wallet doesn't own this wealthyApes!"
        );
        require(
            sha256(bytes(_name)) != sha256(bytes(wealthyApesNames[_tokenId])),
            "New name is same as the current one"
        );
        wealthyApesNames[_tokenId] = _name;

        emit WealthyApesNameChange(msg.sender, _tokenId, _name);
    }

    function viewWealthyApesName(uint256 _tokenId)
        external
        view
        returns (string memory)
    {
        require(_tokenId < totalSupply(), "Choose a wealthyApes within range");
        return wealthyApesNames[_tokenId];
    }

    // GET ALL WEALTHYAPES OF A WALLET AS AN ARRAY OF STRINGS. WOULD BE BETTER MAYBE IF IT RETURNED A STRUCT WITH ID-NAME MATCH
    function wealthyApesNamesOfOwner(address _owner)
        external
        view
        returns (string[] memory)
    {
        uint256 tokenCount = balanceOf(_owner);
        if (tokenCount == 0) {
            // Return an empty array
            return new string[](0);
        } else {
            string[] memory result = new string[](tokenCount);
            uint256 index;
            for (index = 0; index < tokenCount; index++) {
                result[index] = wealthyApesNames[
                    tokenOfOwnerByIndex(_owner, index)
                ];
            }
            return result;
        }
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    )
        internal
        virtual
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable)
    {
        super._beforeTokenTransfer(from, to, tokenId);
    }
}

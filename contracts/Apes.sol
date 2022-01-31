// SPDX-License-Identifier: MIT
/*
    Apes / 2022
*/
pragma solidity ^0.8.6;

// import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";

contract Profile is ERC721EnumerableUpgradeable {
    event NameChange(uint256 indexed tokenId, string newName);
    event BioChange(uint256 indexed tokenId, string bio);

    uint256 public constant NAME_CHANGE_PRICE = 50;
    uint256 public constant BIO_CHANGE_PRICE = 100;

    mapping(uint256 => string) public bio;

    // Mapping from token ID to name
    mapping(uint256 => string) private _tokenName;

    // Mapping if certain name string has already been reserved
    mapping(string => bool) private _nameReserved;

    function changeBio(uint256 _tokenId, string memory _bio) public virtual {
        address owner = ownerOf(_tokenId);
        require(msg.sender == owner, "ERC721: caller is not the owner");

        bio[_tokenId] = _bio;
        emit BioChange(_tokenId, _bio);
    }

    function changeName(uint256 tokenId, string memory newName) public virtual {
        address owner = ownerOf(tokenId);

        require(msg.sender == owner, "ERC721: caller is not the owner");
        require(validateName(newName) == true, "Not a valid new name");
        require(
            sha256(bytes(newName)) != sha256(bytes(_tokenName[tokenId])),
            "New name is same as the current one"
        );
        require(isNameReserved(newName) == false, "Name already reserved");

        // If already named, dereserve old name
        if (bytes(_tokenName[tokenId]).length > 0) {
            toggleReserveName(_tokenName[tokenId], false);
        }
        toggleReserveName(newName, true);
        _tokenName[tokenId] = newName;
        emit NameChange(tokenId, newName);
    }

    /**
     * @dev Reserves the name if isReserve is set to true, de-reserves if set to false
     */
    function toggleReserveName(string memory str, bool isReserve) internal {
        _nameReserved[toLower(str)] = isReserve;
    }

    /**
     * @dev Returns name of the NFT at index.
     */
    function tokenNameByIndex(uint256 index)
        public
        view
        returns (string memory)
    {
        return _tokenName[index];
    }

    /**
     * @dev Returns if the name has been reserved.
     */
    function isNameReserved(string memory nameString)
        public
        view
        returns (bool)
    {
        return _nameReserved[toLower(nameString)];
    }

    function validateName(string memory str) public pure returns (bool) {
        bytes memory b = bytes(str);
        if (b.length < 1) return false;
        if (b.length > 25) return false; // Cannot be longer than 25 characters
        if (b[0] == 0x20) return false; // Leading space
        if (b[b.length - 1] == 0x20) return false; // Trailing space

        bytes1 lastChar = b[0];

        for (uint256 i; i < b.length; i++) {
            bytes1 char = b[i];

            if (char == 0x20 && lastChar == 0x20) return false; // Cannot contain continous spaces

            if (
                !(char >= 0x30 && char <= 0x39) && //9-0
                !(char >= 0x41 && char <= 0x5A) && //A-Z
                !(char >= 0x61 && char <= 0x7A) && //a-z
                !(char == 0x20) //space
            ) return false;

            lastChar = char;
        }

        return true;
    }

    /**
     * @dev Converts the string to lowercase
     */
    function toLower(string memory str) public pure returns (string memory) {
        bytes memory bStr = bytes(str);
        bytes memory bLower = new bytes(bStr.length);
        for (uint256 i = 0; i < bStr.length; i++) {
            // Uppercase character
            if ((uint8(bStr[i]) >= 65) && (uint8(bStr[i]) <= 90)) {
                bLower[i] = bytes1(uint8(bStr[i]) + 32);
            } else {
                bLower[i] = bStr[i];
            }
        }
        return string(bLower);
    }
}

interface IUtilityToken {
    function burn(address _from, uint256 _amount) external;

    function decimals() external pure returns (uint8);
}

interface IStakingPool {
    function startStaking(address _user, uint256 _tokenId) external;

    function stopStaking(address _user, uint256 _tokenId) external;
}

contract BearNFT is Profile, OwnableUpgradeable {
    using SafeMath for uint256;

    enum BearType {
        M1,
        M2,
        M3
    }

    struct BearInfo {
        BearType aType;
        bool bStaked;
        // uint256 lastBreedTime;
    }

    event BearMinted(
        address indexed user,
        uint256 indexed tokenId,
        uint256 indexed aType
    );

    uint256 public constant MINT_PRICE = 90000000000000000; // 0.06 ETH
    uint256 public constant BREED_PRICE = 100000000000000000; // 0.1 ETH
    uint256 public constant EVOLVE_PRICE = 1000000000000000000; // 1 ETH
    // uint256[] private COOLDOWN_TIME_FOR_BREED = [14 days, 0, 7 days];

    uint256[] private START_ID_BY_TYPE;
    uint256[] private MAX_SUPPLY_BY_TYPE;
    uint256[] public totalSupplyByType;

    uint256 public constant MAX_SUPPLY_FOR_FREE = 500;
    uint256 public constant MAX_BEAR_PURCHASE = 20;
    uint256 public constant MAX_FREE_FOR_USER = 10;
    mapping(address => uint256) private claimInFree;

    address public royaltyReceiver;
    uint256 public royaltyPercent;
    uint256 public DENOMINATOR;

    bool public bMintAvailable;
    bool public bStakingAvailable;
    bool public bBreedingAvailable;

    mapping(uint256 => BearInfo) public bear;

    string public _baseTokenURI;

    IUtilityToken private _utilityToken;
    IStakingPool private _pool;

    function initialize()
        public
        initializer
    {
        __ERC721_init("Degen Bear Club", "DBC");

        START_ID_BY_TYPE = [0, 7000, 6800];
        MAX_SUPPLY_BY_TYPE = [6666, 6666, 100];
        totalSupplyByType = [0, 0, 0];

        royaltyReceiver = 0xd8378Be0D049EcE73da320252b6399E9584dE949;
        royaltyPercent = 10;
        DENOMINATOR = 100;

        bMintAvailable = true;
        bStakingAvailable = false;
        bBreedingAvailable = true;

        _baseTokenURI = "https://mintdropz-staging.herokuapp.com/temp/metadata/token/";

        // 250 Apes will be held in the Vault for Promotional purposes
        for (uint256 i = 0; i <6666; i++) mintOne(BearType.M1);
    }

    function setRoyaltyConfig(
        address _royaltyReceiver,
        uint256 _royaltyPercent,
        uint256 _DENOMINATOR
    ) external onlyOwner {
        royaltyReceiver = _royaltyReceiver;
        royaltyPercent = _royaltyPercent;
        DENOMINATOR = _DENOMINATOR;
    }

    /**
     * @dev return the Base URI of the token
     */

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    /**
     * @dev set the _baseTokenURI
     * @param _newURI of the _baseTokenURI
     */

    function setBaseURI(string calldata _newURI) external onlyOwner {
        _baseTokenURI = _newURI;
    }

    function withdraw() public onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "Balance is zero");
        payable(msg.sender).transfer(balance);
    }

    function getBearType(uint256 _tokenId) public view returns (uint256) {
        return uint256(bear[_tokenId].aType);
    }

    function setMintAvailable() external onlyOwner {
        bMintAvailable = true;
    }

    /**
     * @dev free for first 250, 0.06 ETH for afterwards
     */
    function mintNFT(uint256 numberOfTokens) external payable {
        
        require(bMintAvailable, "Minting is not available yet");
        require(
            numberOfTokens > 0 && numberOfTokens <= MAX_BEAR_PURCHASE,
            "Can only mint 20 tokens at a time"
        );
        require(
            totalSupplyByType[uint256(BearType.M1)] <
                MAX_SUPPLY_BY_TYPE[uint256(BearType.M1)],
            "Exceed max supply of Bear NFT"
        );
        if (
            numberOfTokens >
            MAX_SUPPLY_BY_TYPE[uint256(BearType.M1)] -
                totalSupplyByType[uint256(BearType.M1)]
        )
            numberOfTokens =
                MAX_SUPPLY_BY_TYPE[uint256(BearType.M1)] -
                totalSupplyByType[uint256(BearType.M1)];
        uint256 freeMintableCnt = 0;
        uint256 personalFreeMintable = MAX_FREE_FOR_USER -
            claimInFree[msg.sender];
        if (
            personalFreeMintable > 0 &&
            totalSupplyByType[uint256(BearType.M1)] < MAX_SUPPLY_FOR_FREE
        ) {
            freeMintableCnt =
                MAX_SUPPLY_FOR_FREE -
                totalSupplyByType[uint256(BearType.M1)];
            if (freeMintableCnt > personalFreeMintable) {
                freeMintableCnt = personalFreeMintable;
            }
        }
        uint256 payfulAmount = numberOfTokens;
        if (freeMintableCnt > numberOfTokens) {
            freeMintableCnt = numberOfTokens;
            payfulAmount = 0;
        } else {
            payfulAmount = numberOfTokens - freeMintableCnt;
        }
        uint256 royaltyFee = MINT_PRICE
            .mul(numberOfTokens)
            .mul(royaltyPercent)
            .div(DENOMINATOR);
        require(
            msg.value >= MINT_PRICE * payfulAmount + royaltyFee,
            "Invalid Amount"
        );
        uint256 mintIndex = totalSupplyByType[uint256(BearType.M1)];
        totalSupplyByType[uint256(BearType.M1)] += numberOfTokens;
        uint256 restAmount = msg.value - MINT_PRICE * payfulAmount - royaltyFee;
        payable(msg.sender).transfer(restAmount);
        payable(royaltyReceiver).transfer(royaltyFee);
        payable(owner()).transfer(address(this).balance);
        for (uint256 i = 1; i <= numberOfTokens; i++) {
            _safeMint(msg.sender, mintIndex + i);
            bear[mintIndex + i].aType = BearType.M1;
        }
    }

    function mintOne(BearType _type) private {
        require(msg.sender == tx.origin);
        require(
            totalSupplyByType[uint256(_type)] <
                MAX_SUPPLY_BY_TYPE[uint256(_type)],
            "All tokens are minted"
        );

        uint256 tokenId = ++totalSupplyByType[uint256(_type)];
        tokenId += START_ID_BY_TYPE[uint256(_type)];
        _safeMint(msg.sender, tokenId);
        bear[tokenId].aType = _type;

        emit BearMinted(msg.sender, tokenId, uint256(_type));
    }

    function setUtilitytoken(address _addr) external onlyOwner {
        _utilityToken = IUtilityToken(_addr);
    }

    function setStakingPool(address _addr) external onlyOwner {
        _pool = IStakingPool(_addr);
    }

    /*******************************************************************************
     ***                            Staking Logic                                 ***
     ******************************************************************************** */
    function setStakingAvailable() external onlyOwner {
        bStakingAvailable = true;
    }

    function startStaking(uint256 _tokenId) external {
        require(bStakingAvailable, "Staking Mechanism is not started yet");
        require(ownerOf(_tokenId) == msg.sender, "Staking: owner not matched");
        require(
            !bear[_tokenId].bStaked,
            "This Token is already staked. Please try another token."
        );

        _pool.startStaking(msg.sender, _tokenId);
        _safeTransfer(msg.sender, address(_pool), _tokenId, "");
        bear[_tokenId].bStaked = true;
    }

    function stopStaking(uint256 _tokenId) external {
        require(
            bear[_tokenId].bStaked,
            "This token hasn't ever been staked yet."
        );
        _pool.stopStaking(msg.sender, _tokenId);
        _safeTransfer(address(_pool), msg.sender, _tokenId, "");
        bear[_tokenId].bStaked = false;
    }

    /*******************************************************************************
     ***                            Adopting Logic                               ***
     ********************************************************************************/
    function setBreedingAvailable() external onlyOwner {
        bBreedingAvailable = true;
    }

    function canAdopt(uint256 _tokenId) public view returns (bool) {
        // uint256 aType = uint256(apes[_tokenId].aType);

        require(
            bear[_tokenId].aType != BearType.M2,
            "Try adopting with M1 or M3"
        );

        return true;

        // uint256 lastBreedTime = apes[_tokenId].lastBreedTime;
        // uint256 cooldown = COOLDOWN_TIME_FOR_BREED[aType];

        // return (block.timestamp - lastBreedTime) > cooldown;
    }

    function adopt(uint256 _parent) external payable {
        require(bBreedingAvailable, "Adopting M2 is not ready yet");
        require(canAdopt(_parent), "Try adopting with M1 or M3");
        require(msg.value >= BREED_PRICE, "No enough pay to breed");
        require(
            ownerOf(_parent) == msg.sender,
            "Adopting: You're not owner of this token"
        );
        require(
            !bear[_parent].bStaked,
            "This Token is already staked. Please try another token."
        );

        // _utilityToken.burn(
        //     msg.sender,
        //     BREED_PRICE * (10**_utilityToken.decimals())
        // );

        mintOne(BearType.M2);
        // apes[_parent].lastBreedTime = block.timestamp;
    }

    /*******************************************************************************
     ***                            Evolution Logic                              ***
     ********************************************************************************/
    function evolve(uint256 _tokenId) external payable {
        require(bBreedingAvailable, "Evolving Bear is not ready yet");
        require(
            ownerOf(_tokenId) == msg.sender,
            "Evolve: You're not owner of this token"
        );
        require(bear[_tokenId].aType == BearType.M1, "M1 can only evolve M3");
        require(msg.value >= EVOLVE_PRICE, "No enough pay to evolve");
        require(
            !bear[_tokenId].bStaked,
            "This Token is already staked. Please try another token."
        );

        // _utilityToken.burn(
        //     msg.sender,
        //     EVOLVE_PRICE * (10**_utilityToken.decimals())
        // );

        mintOne(BearType.M3);
    }

    /*******************************************************************************
     ***                            Profile Change                               ***
     ********************************************************************************/
    function changeName(uint256 _tokenId, string memory newName)
        public
        override
    {
        require(
            ownerOf(_tokenId) == msg.sender,
            "ChangeName: you're not the owner"
        );
        require(
            !bear[_tokenId].bStaked,
            "This Token is already staked. Please try another token."
        );
        _utilityToken.burn(
            msg.sender,
            NAME_CHANGE_PRICE * (10**_utilityToken.decimals())
        );
        super.changeName(_tokenId, newName);
    }

    function changeBio(uint256 _tokenId, string memory _bio) public override {
        require(
            ownerOf(_tokenId) == msg.sender,
            "ChangeBio: you're not the owner"
        );
        _utilityToken.burn(
            msg.sender,
            BIO_CHANGE_PRICE * (10**_utilityToken.decimals())
        );
        super.changeBio(_tokenId, _bio);
    }
}
// SPDX-License-Identifier: MIT
pragma solidity >=0.8.10;

import "./MintdropzERC721V2.sol";

contract ERC721Factory {
    mapping(address => address) public contractAddresses;
    uint256 public contractCount;
    address private _owner;
    constructor(){
        _owner = msg.sender;
    }
    function createContract(
        string memory _name,
        string memory _symbol,
        uint256 _maxMintdropzPurchase,
        uint256 _MAX_MINTDROPZ,
        uint256 _mintdropzPrice,
        uint256 _DENOMINATOR,
        uint256 _mintdropzReserve,
        address _royaltyReceiver,
        uint256 _royaltyPercent
    ) public {
        MintdropzERC721V2 _contract = new MintdropzERC721V2();
        _contract.initialize(
            _name,
            _symbol,
            _maxMintdropzPurchase,
            _MAX_MINTDROPZ,
            _mintdropzPrice,
            _DENOMINATOR,
            _mintdropzReserve,
            _royaltyReceiver,
            _royaltyPercent,
            _owner
        );
        _contract.transferOwnership(msg.sender);
        contractAddresses[msg.sender] = address(_contract);
        contractCount++;
    }

    function getMyContract() external view returns (address) {
        require(contractAddresses[msg.sender] != address(0));
        return (contractAddresses[msg.sender]);
    }

    function getContractCount() external view returns (uint256) {
        return contractCount;
    }
}

// Last deployed
// 0x9cb5C3BE7a0044C37438a660aA5bF2858B3E5770
// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {SqueekCompanion} from "../../src/SqueekCompanion.sol";

contract ToggleReceiver is IERC721Receiver {
    bool public accepts;

    function setAccepts(bool value) external {
        accepts = value;
    }

    function claim(SqueekCompanion companion) external returns (uint256) {
        return companion.mint();
    }

    function onERC721Received(address, address, uint256, bytes calldata) external view returns (bytes4) {
        return accepts ? IERC721Receiver.onERC721Received.selector : bytes4(0);
    }
}

contract ReentrantReceiver is IERC721Receiver {
    SqueekCompanion private immutable _companion;
    address private immutable _recipient;
    bool public reentered;
    bytes public reentryError;
    uint256 public observedSupply;
    uint256 public observedMintBlock;
    bool public observedEligibility;

    constructor(SqueekCompanion companion, address recipient) {
        _companion = companion;
        _recipient = recipient;
    }

    function claim() external returns (uint256) {
        return _companion.mint();
    }

    function onERC721Received(address, address, uint256 tokenId, bytes calldata) external returns (bytes4) {
        require(msg.sender == address(_companion), "unexpected token");
        observedSupply = _companion.totalSupply();
        observedMintBlock = _companion.mintBlock(tokenId);
        observedEligibility = _companion.hasMinted(address(this));
        _companion.transferFrom(address(this), _recipient, tokenId);
        (reentered, reentryError) = address(_companion).call(abi.encodeCall(SqueekCompanion.mint, ()));
        return IERC721Receiver.onERC721Received.selector;
    }
}

contract NonReceiver {
    function claim(SqueekCompanion companion) external {
        companion.mint();
    }
}

contract RevertingReceiver is IERC721Receiver {
    error ReceiverRefused();

    function claim(SqueekCompanion companion) external {
        companion.mint();
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        revert ReceiverRefused();
    }
}

contract ConstructorFactory {
    function deploy(bytes memory creationCode, bytes32 salt) external returns (SqueekCompanion) {
        address created;
        assembly ("memory-safe") {
            created := create2(0, add(creationCode, 32), mload(creationCode), salt)
        }
        require(created != address(0), "constructor failed");
        return SqueekCompanion(created);
    }
}

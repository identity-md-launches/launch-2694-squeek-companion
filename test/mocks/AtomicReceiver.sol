// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {SqueekCompanion} from "../../src/SqueekCompanion.sol";

/// @dev Executes nested actions in a real receiver callback, all inside the initiating transaction.
contract AtomicReceiver is IERC721Receiver {
    enum Response {
        Accept,
        WrongSelector,
        EmptyRevert,
        CustomRevert
    }

    error Refused(uint256 tokenId);

    SqueekCompanion public immutable companion;
    AtomicReceiver public nested;
    address public forwardTo;
    bool public catchNestedFailure;
    bool public readMetadata;
    Response public response;

    address public observedOperator;
    address public observedFrom;
    address public observedOwner;
    uint256 public observedId;
    uint256 public observedSupply;
    uint256 public observedMintBlock;
    bool public observedHasMinted;
    bytes public observedData;
    bytes32 public observedURIHash;
    bool public nestedSucceeded;
    bytes public nestedResult;

    constructor(SqueekCompanion companion_) {
        companion = companion_;
    }

    function configure(AtomicReceiver nested_, address forwardTo_, bool catchFailure_, Response response_)
        external
    {
        nested = nested_;
        forwardTo = forwardTo_;
        catchNestedFailure = catchFailure_;
        response = response_;
    }

    function setReadMetadata(bool enabled) external {
        readMetadata = enabled;
    }

    function claim() external returns (uint256) {
        return companion.mint();
    }

    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external
        returns (bytes4)
    {
        require(msg.sender == address(companion), "unexpected collection");
        observedOperator = operator;
        observedFrom = from;
        observedOwner = companion.ownerOf(tokenId);
        observedId = tokenId;
        observedSupply = companion.totalSupply();
        observedMintBlock = companion.mintBlock(tokenId);
        observedHasMinted = companion.hasMinted(address(this));
        observedData = data;
        if (readMetadata) observedURIHash = keccak256(bytes(companion.tokenURI(tokenId)));
        if (forwardTo != address(0)) companion.transferFrom(address(this), forwardTo, tokenId);
        if (address(nested) != address(0)) {
            (bool success, bytes memory result) =
                address(nested).call(abi.encodeCall(AtomicReceiver.claim, ()));
            nestedSucceeded = success;
            nestedResult = result;
            if (!success && !catchNestedFailure) {
                assembly ("memory-safe") { revert(add(result, 32), mload(result)) }
            }
        }
        if (response == Response.WrongSelector) return bytes4(0);
        if (response == Response.EmptyRevert) {
            assembly ("memory-safe") { revert(0, 0) }
        }
        if (response == Response.CustomRevert) revert Refused(tokenId);
        return IERC721Receiver.onERC721Received.selector;
    }
}

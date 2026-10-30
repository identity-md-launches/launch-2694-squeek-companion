// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {SqueekCompanion} from "../../src/SqueekCompanion.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ToggleReceiver} from "../mocks/MintReceivers.sol";

/// @dev Closed actor set with an independent ledger. Predictions never read ownerOf/getApproved/hasMinted.
contract CompanionLedgerHandler is Test {
    address private constant RESERVE = 0x3C7838665Ff8215c95500E1a6306e19E146674a0;
    uint256 public constant ACTORS = 9;
    SqueekCompanion public immutable companion;
    ToggleReceiver public immutable receiver;
    uint256 public publicMints;
    mapping(uint256 => address) public expectedOwner;
    mapping(uint256 => address) public expectedApproval;
    mapping(uint256 => uint256) public expectedMintBlock;
    mapping(address => uint256) public expectedBalance;
    mapping(address => bool) public claimed;
    mapping(address => mapping(address => bool)) public operators;
    uint256[] private _touched;
    mapping(uint256 => bool) private _seen;

    struct TransferCase {
        uint256 id;
        address owner;
        address caller;
        address from;
        address to;
        bool safe;
        bool withData;
        bool accepts;
    }

    constructor(SqueekCompanion companion_, uint256 seededClaims) {
        companion = companion_;
        receiver = new ToggleReceiver();
        // Seed through real calls, never storage writes. Consolidation keeps balances enumerable.
        for (uint256 i; i < seededClaims; ++i) {
            address wallet = address(uint160(0x80000 + i));
            vm.prank(wallet);
            assertEq(companion.mint(), 100 + i);
            vm.prank(wallet);
            companion.transferFrom(wallet, RESERVE, 100 + i);
        }
        publicMints = seededClaims;
        for (uint256 id = 1; id <= 99 + seededClaims; ++id) {
            expectedOwner[id] = RESERVE;
            expectedMintBlock[id] = block.number;
        }
        expectedBalance[RESERVE] = 99 + seededClaims;
        _touch(1);
        _touch(99);
        _touch(99 + seededClaims);
    }

    function actor(uint256 seed) public view returns (address) {
        uint256 index = seed % ACTORS;
        if (index == 0) return RESERVE;
        if (index == 8) return address(receiver);
        return address(uint160(0x60000 + index));
    }

    function mint(uint256 actorSeed, uint16 blockStep, bool accepts) external {
        uint256 mintAt = vm.getBlockNumber() + bound(blockStep, 0, 100);
        vm.roll(mintAt);
        address caller = actor(actorSeed);
        receiver.setAccepts(accepts);
        bytes memory expectedError;
        if (claimed[caller]) {
            expectedError = abi.encodeWithSelector(SqueekCompanion.AlreadyMinted.selector);
        } else if (publicMints == 900) {
            expectedError = abi.encodeWithSelector(SqueekCompanion.PublicSupplyExhausted.selector);
        } else if (caller == address(receiver) && !accepts) {
            expectedError = abi.encodeWithSelector(IERC721Errors.ERC721InvalidReceiver.selector, caller);
        }
        vm.prank(caller);
        (bool success, bytes memory result) =
            address(companion).call(abi.encodeCall(SqueekCompanion.mint, ()));
        _assertOutcome(success, result, expectedError);
        if (success) {
            uint256 expectedId = 100 + publicMints;
            assertEq(abi.decode(result, (uint256)), expectedId, "mint returned another wallet's token");
            ++publicMints;
            claimed[caller] = true;
            expectedOwner[expectedId] = caller;
            ++expectedBalance[caller];
            expectedMintBlock[expectedId] = mintAt;
            _touch(expectedId);
        }
    }

    function approve(uint256 tokenSeed, uint8 callerSeed, uint8 delegateSeed, bool asOwner, bool clear)
        external
    {
        uint256 id = _token(tokenSeed);
        address owner = expectedOwner[id];
        address caller = asOwner ? owner : actor(callerSeed);
        address delegate = clear ? address(0) : actor(delegateSeed);
        bytes memory expectedError;
        if (caller != owner && !operators[owner][caller]) {
            expectedError = abi.encodeWithSelector(IERC721Errors.ERC721InvalidApprover.selector, caller);
        }
        vm.prank(caller);
        (bool success, bytes memory result) =
            address(companion).call(abi.encodeCall(companion.approve, (delegate, id)));
        _assertOutcome(success, result, expectedError);
        if (success) expectedApproval[id] = delegate;
        _touch(id);
    }

    function setOperator(uint8 ownerSeed, uint8 delegateSeed, bool enabled, bool zeroOperator) external {
        address owner = actor(ownerSeed);
        address delegate = zeroOperator ? address(0) : actor(delegateSeed);
        bytes memory expectedError;
        if (zeroOperator) {
            expectedError = abi.encodeWithSelector(IERC721Errors.ERC721InvalidOperator.selector, address(0));
        }
        vm.prank(owner);
        (bool success, bytes memory result) =
            address(companion).call(abi.encodeCall(companion.setApprovalForAll, (delegate, enabled)));
        _assertOutcome(success, result, expectedError);
        if (success) operators[owner][delegate] = enabled;
    }

    /// @dev Flags exercise owner/operator/stranger calls, incorrect from, self/zero destinations,
    /// both safe overloads, ordinary transfers, and accepting/rejecting receivers.
    function transfer(uint256 tokenSeed, uint8 callerSeed, uint8 recipientSeed, uint8 flags) external {
        TransferCase memory c;
        c.id = _token(tokenSeed);
        c.owner = expectedOwner[c.id];
        c.caller = flags & 1 != 0 ? c.owner : actor(callerSeed);
        c.from = flags & 2 != 0 ? _other(c.owner) : c.owner;
        c.safe = flags & 4 != 0;
        c.withData = flags & 8 != 0;
        c.accepts = flags & 16 != 0;
        c.to = flags & 32 != 0 ? address(0) : flags & 64 != 0 ? c.owner : actor(recipientSeed);
        vm.roll(block.number + 1);
        _transfer(c);
    }

    function roundTrip(uint256 tokenSeed, uint8 recipientSeed) external {
        uint256 id = _token(tokenSeed);
        address owner = expectedOwner[id];
        address destination = actor(recipientSeed);
        vm.prank(owner);
        companion.transferFrom(owner, destination, id);
        assertEq(companion.ownerOf(id), destination);
        assertEq(companion.getApproved(id), address(0));
        vm.roll(block.number + 1);
        vm.prank(destination);
        companion.transferFrom(destination, owner, id);
        expectedApproval[id] = address(0);
        _touch(id);
        // Owners, balances, claim flags and mint blocks must all return to/remain at the model values.
        _assertToken(id);
    }

    function attackReserve(uint8 rawId, uint8 callerSeed) external {
        uint256 id = bound(rawId, 1, 99);
        address thief = actor(callerSeed);
        // This follows the same permission model even after the reserve holder authorizes transfers.
        TransferCase memory c =
            TransferCase(id, expectedOwner[id], thief, RESERVE, thief, false, false, false);
        _transfer(c);
    }

    function mintWithValue(uint8 callerSeed, uint96 rawValue) external {
        address caller = actor(callerSeed);
        uint256 value = bound(rawValue, 1, 1 ether);
        vm.deal(caller, value);
        vm.prank(caller);
        (bool success,) = address(companion).call{value: value}(abi.encodeCall(SqueekCompanion.mint, ()));
        assertFalse(success, "free mint accepted ETH");
        assertEq(caller.balance, value, "rejected payment was not restored");
    }

    function assertModel() external view {
        assertEq(companion.publicMinted(), publicMints, "public allocation diverged");
        assertEq(companion.totalSupply(), 99 + publicMints, "supply diverged");
        assertLe(publicMints, 900);
        uint256 balances;
        for (uint256 i; i < ACTORS; ++i) {
            address wallet = actor(i);
            uint256 balance = companion.balanceOf(wallet);
            assertEq(balance, expectedBalance[wallet], "balance diverged from independent ledger");
            balances += balance;
            assertEq(companion.hasMinted(wallet), claimed[wallet], "lifetime claim changed");
            for (uint256 j; j < ACTORS; ++j) {
                address delegate = actor(j);
                assertEq(companion.isApprovedForAll(wallet, delegate), operators[wallet][delegate]);
            }
        }
        assertEq(balances, 99 + publicMints, "token conservation failed");
        assertEq(address(companion).balance, 0);
        for (uint256 i; i < _touched.length; ++i) {
            _assertToken(_touched[i]);
        }
    }

    /// @dev Full scan once per sequence catches any mutation of tokens that were never selected.
    function assertEveryToken() external view {
        for (uint256 id = 1; id <= 99 + publicMints; ++id) {
            _assertToken(id);
        }
    }

    function _transfer(TransferCase memory c) private {
        receiver.setAccepts(c.accepts);
        bytes memory expectedError;
        if (c.to == address(0)) {
            expectedError = abi.encodeWithSelector(IERC721Errors.ERC721InvalidReceiver.selector, address(0));
        } else if (c.caller != c.owner && expectedApproval[c.id] != c.caller && !operators[c.owner][c.caller])
        {
            expectedError =
                abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, c.caller, c.id);
        } else if (c.from != c.owner) {
            expectedError =
                abi.encodeWithSelector(IERC721Errors.ERC721IncorrectOwner.selector, c.from, c.id, c.owner);
        } else if (c.safe && c.to == address(receiver) && !c.accepts) {
            expectedError = abi.encodeWithSelector(IERC721Errors.ERC721InvalidReceiver.selector, c.to);
        }

        bytes memory callData;
        if (!c.safe) {
            callData = abi.encodeCall(companion.transferFrom, (c.from, c.to, c.id));
        } else if (c.withData) {
            callData = abi.encodeWithSignature(
                "safeTransferFrom(address,address,uint256,bytes)", c.from, c.to, c.id, hex"cafe"
            );
        } else {
            callData =
                abi.encodeWithSignature("safeTransferFrom(address,address,uint256)", c.from, c.to, c.id);
        }
        vm.prank(c.caller);
        (bool success, bytes memory result) = address(companion).call(callData);
        _assertOutcome(success, result, expectedError);
        if (success) {
            --expectedBalance[c.owner];
            ++expectedBalance[c.to];
            expectedOwner[c.id] = c.to;
            expectedApproval[c.id] = address(0);
        }
        _touch(c.id);
        _assertToken(c.id);
    }

    function _assertOutcome(bool success, bytes memory result, bytes memory expectedError) private pure {
        if (expectedError.length == 0) {
            assertTrue(success, "valid operation unexpectedly reverted");
        } else {
            assertFalse(success, "forbidden operation unexpectedly succeeded");
            assertEq(result, expectedError, "unexpected failure reason");
        }
    }

    function _assertToken(uint256 id) private view {
        assertEq(companion.ownerOf(id), expectedOwner[id], "owner diverged");
        assertEq(companion.getApproved(id), expectedApproval[id], "token approval diverged");
        assertEq(companion.mintBlock(id), expectedMintBlock[id], "mint block changed");
    }

    function _token(uint256 seed) private view returns (uint256) {
        // Half of the selections stress public IDs, even in a freshly deployed collection.
        if (publicMints > 0 && seed & 1 != 0) return 100 + ((seed >> 1) % publicMints);
        return 1 + ((seed >> 1) % 99);
    }

    function _other(address owner) private view returns (address) {
        return owner == actor(1) ? actor(2) : actor(1);
    }

    function _touch(uint256 id) private {
        if (!_seen[id]) {
            _seen[id] = true;
            _touched.push(id);
        }
    }
}

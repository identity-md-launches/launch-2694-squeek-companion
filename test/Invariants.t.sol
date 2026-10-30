// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {CompanionTestBase, SqueekCompanion} from "./helpers/CompanionTestBase.sol";

contract MintTransferHandler is Test {
    SqueekCompanion public immutable companion;
    uint256 public constant ACTORS = 24;
    uint256 public successfulMints;
    mapping(address => uint256) public claims;

    constructor(SqueekCompanion companion_) {
        companion = companion_;
    }

    function actor(uint256 index) public pure returns (address) {
        return address(uint160(0x30000 + (index % ACTORS)));
    }

    function mint(uint8 index) external {
        address caller = actor(index);
        vm.prank(caller);
        (bool success, bytes memory result) =
            address(companion).call(abi.encodeCall(SqueekCompanion.mint, ()));
        if (claims[caller] == 0) {
            assertTrue(success, "eligible mint failed");
            ++claims[caller];
            ++successfulMints;
            assertEq(abi.decode(result, (uint256)), 99 + successfulMints);
        } else {
            assertFalse(success, "duplicate mint succeeded");
            assertEq(result, abi.encodeWithSelector(SqueekCompanion.AlreadyMinted.selector));
        }
    }

    function transfer(uint256 seed, uint8 recipient) external {
        if (successfulMints == 0) return;
        uint256 tokenId = 100 + (seed % successfulMints);
        address holder = companion.ownerOf(tokenId);
        vm.prank(holder);
        companion.transferFrom(holder, actor(recipient), tokenId);
    }

    function unauthorizedTransfer(uint256 seed, uint8 caller) external {
        if (successfulMints == 0) return;
        uint256 tokenId = 100 + (seed % successfulMints);
        address holder = companion.ownerOf(tokenId);
        address thief = actor(caller);
        if (thief == holder) return;
        vm.prank(thief);
        (bool success,) =
            address(companion).call(abi.encodeCall(companion.transferFrom, (holder, thief, tokenId)));
        assertFalse(success, "unauthorized transfer succeeded");
        assertEq(companion.ownerOf(tokenId), holder);
    }
}

contract CompanionInvariantTest is CompanionTestBase {
    MintTransferHandler private handler;

    function setUp() public override {
        super.setUp();
        handler = new MintTransferHandler(companion);
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = MintTransferHandler.mint.selector;
        selectors[1] = MintTransferHandler.transfer.selector;
        selectors[2] = MintTransferHandler.unauthorizedTransfer.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariantSupplyAndBalancesAreConserved() public view {
        uint256 balanceSum = companion.balanceOf(RESERVE);
        for (uint256 i; i < handler.ACTORS(); ++i) {
            balanceSum += companion.balanceOf(handler.actor(i));
        }
        assertEq(companion.totalSupply(), 99 + handler.successfulMints());
        assertEq(companion.publicMinted(), handler.successfulMints());
        assertEq(balanceSum, companion.totalSupply());
        assertLe(companion.totalSupply(), 999);
    }

    function invariantReserveNeverEntersPublicMintPool() public view {
        assertEq(companion.balanceOf(RESERVE), 99);
        for (uint256 id = 1; id <= 99; ++id) {
            assertEq(companion.ownerOf(id), RESERVE);
        }
    }

    function invariantLifetimeClaimsPersistAfterArbitraryTransfers() public view {
        for (uint256 i; i < handler.ACTORS(); ++i) {
            address wallet = handler.actor(i);
            assertLe(handler.claims(wallet), 1);
            assertEq(companion.hasMinted(wallet), handler.claims(wallet) == 1);
        }
    }

    function invariantMintedPublicIdsExistAndMintBlocksNeverChange() public view {
        for (uint256 i; i < handler.successfulMints(); ++i) {
            assertTrue(companion.ownerOf(100 + i) != address(0));
            assertEq(companion.mintBlock(100 + i), 20_000_000);
        }
    }
}

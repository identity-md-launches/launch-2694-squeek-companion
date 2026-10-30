// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {CompanionTestBase, SqueekCompanion} from "./helpers/CompanionTestBase.sol";
import {AtomicReceiver} from "./mocks/AtomicReceiver.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract CallbackAtomicityTest is CompanionTestBase {
    AtomicReceiver private outer;
    AtomicReceiver private inner;

    function setUp() public override {
        super.setUp();
        outer = new AtomicReceiver(companion);
        inner = new AtomicReceiver(companion);
    }

    function testDistinctWalletNestedMintsReturnTheirOwnIds() public {
        outer.configure(inner, bob, false, AtomicReceiver.Response.Accept);
        vm.roll(20_000_077);
        assertEq(outer.claim(), 100, "outer return value must survive nested mint");
        assertTrue(outer.nestedSucceeded());
        assertEq(abi.decode(outer.nestedResult(), (uint256)), 101);
        assertEq(outer.observedSupply(), 100);
        assertEq(inner.observedSupply(), 101);
        assertEq(companion.ownerOf(100), bob);
        assertEq(companion.ownerOf(101), address(inner));
        assertEq(companion.balanceOf(address(outer)), 0);
        assertEq(companion.totalSupply(), 101);
        assertEq(companion.publicMinted(), 2);
        assertTrue(companion.hasMinted(address(outer)));
        assertTrue(companion.hasMinted(address(inner)));
        assertFalse(companion.hasMinted(bob));
        assertEq(companion.mintBlock(100), 20_000_077);
        assertEq(companion.mintBlock(101), 20_000_077);
        vm.expectRevert(SqueekCompanion.AlreadyMinted.selector);
        outer.claim();
        vm.expectRevert(SqueekCompanion.AlreadyMinted.selector);
        inner.claim();
    }

    function testOuterRejectionRollsBackNestedMintAndForwardedToken() public {
        outer.configure(inner, bob, false, AtomicReceiver.Response.CustomRevert);
        vm.expectRevert(abi.encodeWithSelector(AtomicReceiver.Refused.selector, 100));
        outer.claim();
        assertEq(companion.publicMinted(), 0);
        assertEq(companion.totalSupply(), 99);
        assertFalse(companion.hasMinted(address(outer)));
        assertFalse(companion.hasMinted(address(inner)));
        assertEq(companion.balanceOf(bob), 0);
        assertEq(companion.balanceOf(address(inner)), 0);
        assertEq(outer.observedId(), 0);
        assertEq(inner.observedId(), 0);
        _assertAbsent(100);
        _assertAbsent(101);

        // A later transaction can claim the exact IDs, with its own immutable mint block.
        vm.roll(20_000_099);
        outer.configure(inner, bob, false, AtomicReceiver.Response.Accept);
        assertEq(outer.claim(), 100);
        assertEq(companion.ownerOf(101), address(inner));
        assertEq(companion.mintBlock(100), 20_000_099);
        assertEq(companion.mintBlock(101), 20_000_099);
    }

    function testRejectedInnerMintCanBeCaughtAndRetriedIndependently() public {
        inner.configure(AtomicReceiver(address(0)), alice, false, AtomicReceiver.Response.CustomRevert);
        outer.configure(inner, bob, true, AtomicReceiver.Response.Accept);
        assertEq(outer.claim(), 100);
        assertFalse(outer.nestedSucceeded());
        assertEq(outer.nestedResult(), abi.encodeWithSelector(AtomicReceiver.Refused.selector, 101));
        assertEq(companion.publicMinted(), 1);
        assertFalse(companion.hasMinted(address(inner)));
        assertEq(companion.balanceOf(alice), 0);
        _assertAbsent(101);
        inner.configure(AtomicReceiver(address(0)), alice, false, AtomicReceiver.Response.Accept);
        assertEq(inner.claim(), 101);
        assertEq(companion.ownerOf(101), alice);
        assertEq(companion.publicMinted(), 2);
    }

    function testNestedMintsCanConsumeExactlyLastTwoPublicSlots() public {
        _fillPublic(898);
        outer.configure(inner, bob, false, AtomicReceiver.Response.Accept);
        assertEq(outer.claim(), 998);
        assertEq(abi.decode(outer.nestedResult(), (uint256)), 999);
        assertEq(companion.totalSupply(), 999);
        assertEq(companion.balanceOf(RESERVE), 99);
        vm.prank(alice);
        vm.expectRevert(SqueekCompanion.PublicSupplyExhausted.selector);
        companion.mint();
        _assertAbsent(1000);
    }

    function testLastSlotIsVisibleToNestedWalletBeforeOuterCallbackReturns() public {
        _fillPublic(899);
        outer.configure(inner, bob, true, AtomicReceiver.Response.Accept);
        assertEq(outer.claim(), 999);
        assertFalse(outer.nestedSucceeded());
        assertEq(outer.nestedResult(), abi.encodeWithSelector(SqueekCompanion.PublicSupplyExhausted.selector));
        assertEq(companion.publicMinted(), 900);
        assertEq(companion.totalSupply(), 999);
        assertFalse(companion.hasMinted(address(inner)));
        assertEq(companion.ownerOf(999), bob);
        assertEq(companion.balanceOf(RESERVE), 99);
        _assertAbsent(1000);
    }

    function testUncaughtNestedExhaustionRestoresLastSlot() public {
        _fillPublic(899);
        outer.configure(inner, bob, false, AtomicReceiver.Response.Accept);
        vm.expectRevert(SqueekCompanion.PublicSupplyExhausted.selector);
        outer.claim();
        assertEq(companion.publicMinted(), 899);
        assertEq(companion.totalSupply(), 998);
        assertFalse(companion.hasMinted(address(outer)));
        assertFalse(companion.hasMinted(address(inner)));
        assertEq(companion.balanceOf(bob), 0);
        _assertAbsent(999);
        assertEq(inner.claim(), 999);
        assertEq(companion.ownerOf(999), address(inner));
    }

    function testAllReceiverRejectionModesPreserveEligibilityAndId() public {
        for (uint256 mode = 1; mode <= 3; ++mode) {
            outer.configure(AtomicReceiver(address(0)), bob, false, AtomicReceiver.Response(mode));
            bytes memory expected = mode == 3
                ? abi.encodeWithSelector(AtomicReceiver.Refused.selector, 100)
                : abi.encodeWithSelector(IERC721Errors.ERC721InvalidReceiver.selector, address(outer));
            vm.expectRevert(expected);
            outer.claim();
            assertEq(companion.publicMinted(), 0);
            assertFalse(companion.hasMinted(address(outer)));
            assertEq(companion.balanceOf(bob), 0);
            _assertAbsent(100);
        }
        outer.configure(AtomicReceiver(address(0)), bob, false, AtomicReceiver.Response.Accept);
        assertEq(outer.claim(), 100);
        assertEq(companion.ownerOf(100), bob);
    }

    function testMintCallbackSeesCommittedAccountingAndUsableMetadata() public {
        outer.setReadMetadata(true);
        vm.roll(20_000_456);
        assertEq(outer.claim(), 100);
        assertEq(outer.observedOperator(), address(outer));
        assertEq(outer.observedFrom(), address(0));
        assertEq(outer.observedOwner(), address(outer));
        assertEq(outer.observedId(), 100);
        assertEq(outer.observedSupply(), 100);
        assertEq(outer.observedMintBlock(), 20_000_456);
        assertTrue(outer.observedHasMinted());
        assertEq(outer.observedData(), hex"");
        assertEq(outer.observedURIHash(), keccak256(bytes(companion.tokenURI(100))));
    }

    /// forge-config: default.fuzz.runs = 256
    function testFuzzSafeTransferForwardsExactCallbackArguments(bytes memory data) public {
        uint256 id = _mint(alice);
        vm.prank(alice);
        companion.approve(bob, id);
        vm.prank(bob);
        companion.safeTransferFrom(alice, address(outer), id, data);
        assertEq(outer.observedOperator(), bob);
        assertEq(outer.observedFrom(), alice);
        assertEq(outer.observedData(), data);
        assertEq(outer.observedOwner(), address(outer));
        assertEq(outer.observedId(), id);
        assertFalse(outer.observedHasMinted());
        assertEq(companion.getApproved(id), address(0));
        // Receiving a transfer did not consume this receiver's lifetime public claim.
        assertEq(outer.claim(), 101);
        assertEq(companion.balanceOf(address(outer)), 2);
    }

    function testRejectedSafeTransferRestoresApprovalAndNestedMint() public {
        _rejectedTransferRestoresEverything(_mint(alice), alice);
    }

    function testRejectedReserveSafeTransferRestoresApprovalAndNestedMint() public {
        _rejectedTransferRestoresEverything(99, RESERVE);
        assertEq(companion.balanceOf(RESERVE), 99);
        assertEq(companion.publicMinted(), 1, "only the independent retry consumed a claim");
    }

    function _rejectedTransferRestoresEverything(uint256 id, address owner) private {
        uint256 supplyBefore = companion.totalSupply();
        uint256 balanceBefore = companion.balanceOf(owner);
        uint256 mintedAt = companion.mintBlock(id);
        outer.configure(inner, bob, false, AtomicReceiver.Response.WrongSelector);
        vm.prank(owner);
        companion.approve(bob, id);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidReceiver.selector, address(outer)));
        companion.safeTransferFrom(owner, address(outer), id, hex"decafbad");
        assertEq(companion.ownerOf(id), owner);
        assertEq(companion.balanceOf(owner), balanceBefore);
        assertEq(companion.balanceOf(bob), 0);
        assertEq(companion.balanceOf(address(outer)), 0);
        assertEq(companion.balanceOf(address(inner)), 0);
        assertEq(companion.getApproved(id), bob);
        assertEq(companion.totalSupply(), supplyBefore);
        assertEq(companion.mintBlock(id), mintedAt);
        assertFalse(companion.hasMinted(address(inner)));
        assertFalse(companion.hasMinted(address(outer)));
        _assertAbsent(supplyBefore + 1);
        assertEq(inner.claim(), supplyBefore + 1);
    }

    function _fillPublic(uint256 count) private {
        for (uint256 i; i < count; ++i) {
            _mint(address(uint160(0x50000 + i)));
        }
        assertEq(companion.publicMinted(), count);
    }

    function _assertAbsent(uint256 id) private {
        bytes memory expected = abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, id);
        vm.expectRevert(expected);
        companion.ownerOf(id);
        vm.expectRevert(expected);
        companion.mintBlock(id);
        vm.expectRevert(expected);
        companion.tokenURI(id);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {CompanionTestBase} from "./helpers/CompanionTestBase.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ToggleReceiver, NonReceiver} from "./mocks/MintReceivers.sol";

contract ERC721Test is CompanionTestBase {
    function testTokenApprovalAndTransferClearApproval() public {
        uint256 id = _mint(alice);
        vm.prank(alice);
        companion.approve(bob, id);
        assertEq(companion.getApproved(id), bob);
        vm.prank(bob);
        companion.transferFrom(alice, bob, id);
        assertEq(companion.ownerOf(id), bob);
        assertEq(companion.getApproved(id), address(0));
        assertEq(companion.balanceOf(alice), 0);
        assertEq(companion.balanceOf(bob), 1);
        assertEq(companion.mintBlock(id), 20_000_000);
    }

    function testOperatorApprovalAndRevocation() public {
        uint256 id = _mint(alice);
        vm.prank(alice);
        companion.setApprovalForAll(bob, true);
        assertTrue(companion.isApprovedForAll(alice, bob));
        vm.prank(bob);
        companion.safeTransferFrom(alice, bob, id);
        vm.prank(bob);
        companion.transferFrom(bob, alice, id);
        vm.prank(alice);
        companion.setApprovalForAll(bob, false);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, bob, id));
        companion.transferFrom(alice, bob, id);
    }

    function testUnauthorizedApprovalRejected() public {
        uint256 id = _mint(alice);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidApprover.selector, bob));
        companion.approve(bob, id);
    }

    function testWrongFromAndZeroRecipientRejected() public {
        uint256 id = _mint(alice);
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721IncorrectOwner.selector, bob, id, alice));
        companion.transferFrom(bob, bob, id);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidReceiver.selector, address(0)));
        companion.transferFrom(alice, address(0), id);
        vm.stopPrank();
        assertEq(companion.ownerOf(id), alice);
    }

    function testSafeTransferAcceptingReceiverWithData() public {
        uint256 id = _mint(alice);
        ToggleReceiver receiver = new ToggleReceiver();
        receiver.setAccepts(true);
        vm.prank(alice);
        companion.safeTransferFrom(alice, address(receiver), id, hex"1234");
        assertEq(companion.ownerOf(id), address(receiver));
    }

    function testSafeTransferRejectsMissingReceiverAndPreservesOwner() public {
        uint256 id = _mint(alice);
        NonReceiver receiver = new NonReceiver();
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IERC721Errors.ERC721InvalidReceiver.selector, address(receiver))
        );
        companion.safeTransferFrom(alice, address(receiver), id);
        assertEq(companion.ownerOf(id), alice);
    }

    function testNonexistentTokenAndZeroBalanceQueriesRevert() public {
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 0));
        companion.ownerOf(0);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 100));
        companion.getApproved(100);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidOwner.selector, address(0)));
        companion.balanceOf(address(0));
    }
}

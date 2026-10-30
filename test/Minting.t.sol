// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {CompanionTestBase, SqueekCompanion} from "./helpers/CompanionTestBase.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {
    ToggleReceiver,
    ReentrantReceiver,
    NonReceiver,
    RevertingReceiver,
    ConstructorFactory
} from "./mocks/MintReceivers.sol";

contract MintingTest is CompanionTestBase {
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    function testExactCollectionIdentityAndInterfaces() public view {
        assertEq(companion.name(), "_Squeek Companion");
        assertEq(companion.symbol(), "SQCOM");
        assertTrue(companion.supportsInterface(0x80ac58cd)); // ERC-721
        assertTrue(companion.supportsInterface(0x5b5e139f)); // metadata
        assertTrue(companion.supportsInterface(0x01ffc9a7)); // ERC-165
        assertFalse(companion.supportsInterface(0xffffffff));
        assertFalse(companion.supportsInterface(0x780e9d63)); // not enumerable
        assertEq(companion.RESERVE_OWNER(), RESERVE);
        assertEq(address(companion.SQUEEK_CORE()), CORE);
        assertEq(companion.MAX_SUPPLY(), 999);
        assertEq(companion.RESERVED_SUPPLY(), 99);
        assertEq(companion.PUBLIC_SUPPLY(), 900);
    }

    function testReserveHeldByNamedOwnerAtDeployment() public view {
        assertEq(companion.totalSupply(), 99);
        assertEq(companion.publicMinted(), 0);
        assertEq(companion.balanceOf(RESERVE), 99);
        assertFalse(companion.hasMinted(RESERVE));
        for (uint256 tokenId = 1; tokenId <= 99; ++tokenId) {
            assertEq(companion.ownerOf(tokenId), RESERVE);
            assertEq(companion.mintBlock(tokenId), 20_000_000);
        }
    }

    function testConstructorNeedsNoExternalCodeAndFactoryHasNoPrivilege() public {
        vm.etch(CORE, hex"");
        // A rejecting contract at the named reserve address must not be called in construction.
        RevertingReceiver rejecting = new RevertingReceiver();
        vm.etch(RESERVE, address(rejecting).code);
        ConstructorFactory factory = new ConstructorFactory();
        bytes memory creationCode = type(SqueekCompanion).creationCode;
        assertLe(creationCode.length, 49_152);
        // Raw CREATE2 avoids Foundry's dynamic test-linking replacement of `new` expressions.
        SqueekCompanion deployed = factory.deploy(creationCode, keccak256("empty-chain rehearsal"));
        assertEq(deployed.balanceOf(RESERVE), 99);
        assertEq(deployed.balanceOf(address(factory)), 0);
        vm.prank(address(factory));
        vm.expectRevert(
            abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, address(factory), 1)
        );
        deployed.transferFrom(RESERVE, address(factory), 1);
    }

    function testFreeMintRecordsOwnerSupplyAndStaticBlockAndEmitsTransfer() public {
        vm.roll(20_000_123);
        vm.expectEmit(true, true, true, true, address(companion));
        emit Transfer(address(0), alice, 100);
        uint256 tokenId = _mint(alice);
        assertEq(tokenId, 100);
        assertEq(companion.ownerOf(tokenId), alice);
        assertEq(companion.balanceOf(alice), 1);
        assertEq(companion.totalSupply(), 100);
        assertEq(companion.publicMinted(), 1);
        assertEq(companion.mintBlock(tokenId), 20_000_123);
        assertTrue(companion.hasMinted(alice));
        assertEq(address(companion).balance, 0);
    }

    function testOneLifetimePublicMintPerWallet() public {
        _mint(alice);
        vm.prank(alice);
        vm.expectRevert(SqueekCompanion.AlreadyMinted.selector);
        companion.mint();
        assertEq(companion.totalSupply(), 100);
    }

    function testTransferringAwayDoesNotRestoreMintEligibility() public {
        uint256 tokenId = _mint(alice);
        vm.prank(alice);
        companion.transferFrom(alice, bob, tokenId);
        assertEq(companion.balanceOf(alice), 0);
        vm.prank(alice);
        vm.expectRevert(SqueekCompanion.AlreadyMinted.selector);
        companion.mint();
    }

    function testRecipientCanClaimOnceEvenWhenAlreadyHoldingAnotherToken() public {
        uint256 aliceToken = _mint(alice);
        vm.prank(alice);
        companion.transferFrom(alice, bob, aliceToken);
        uint256 bobToken = _mint(bob);
        assertEq(bobToken, 101);
        assertEq(companion.balanceOf(bob), 2);
        assertTrue(companion.hasMinted(bob));
    }

    function testReserveOwnerCanClaimOneOfThePublicAllocation() public {
        assertEq(_mint(RESERVE), 100);
        assertEq(companion.balanceOf(RESERVE), 100);
        assertEq(companion.publicMinted(), 1);
        vm.prank(RESERVE);
        vm.expectRevert(SqueekCompanion.AlreadyMinted.selector);
        companion.mint();
    }

    function testAll900PublicMintsReach999AndCannotTouchReserve() public {
        for (uint256 i; i < 900; ++i) {
            address claimant = address(uint160(0x10000 + i));
            assertEq(_mint(claimant), 100 + i);
            assertEq(companion.ownerOf(100 + i), claimant);
        }
        assertEq(companion.publicMinted(), 900);
        assertEq(companion.totalSupply(), 999);
        assertEq(companion.balanceOf(RESERVE), 99);
        for (uint256 i = 1; i <= 99; ++i) {
            assertEq(companion.ownerOf(i), RESERVE);
        }

        vm.prank(alice);
        vm.expectRevert(SqueekCompanion.PublicSupplyExhausted.selector);
        companion.mint();
        vm.prank(RESERVE);
        vm.expectRevert(SqueekCompanion.PublicSupplyExhausted.selector);
        companion.mint();
        assertFalse(companion.hasMinted(alice));
        assertFalse(companion.hasMinted(RESERVE));
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 1000));
        companion.ownerOf(1000);
    }

    function testMintRejectsEtherWithoutConsumingEligibility() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool success,) = address(companion).call{value: 1 wei}(abi.encodeCall(SqueekCompanion.mint, ()));
        assertFalse(success);
        assertEq(companion.publicMinted(), 0);
        assertFalse(companion.hasMinted(alice));
        assertEq(alice.balance, 1 ether);
        assertEq(_mint(alice), 100);
    }

    function testDirectEtherRejected() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool success,) = address(companion).call{value: 1 wei}("");
        assertFalse(success);
        assertEq(address(companion).balance, 0);
    }

    function testContractWalletCanMintWithReceiverHook() public {
        ToggleReceiver receiver = new ToggleReceiver();
        receiver.setAccepts(true);
        assertEq(receiver.claim(companion), 100);
        assertEq(companion.ownerOf(100), address(receiver));
        assertTrue(companion.hasMinted(address(receiver)));
    }

    function testInvalidReceiverRollsBackThenCanRetry() public {
        ToggleReceiver receiver = new ToggleReceiver();
        vm.expectRevert(
            abi.encodeWithSelector(IERC721Errors.ERC721InvalidReceiver.selector, address(receiver))
        );
        receiver.claim(companion);
        assertEq(companion.publicMinted(), 0);
        assertEq(companion.totalSupply(), 99);
        assertEq(companion.balanceOf(address(receiver)), 0);
        assertFalse(companion.hasMinted(address(receiver)));
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 100));
        companion.mintBlock(100);
        receiver.setAccepts(true);
        assertEq(receiver.claim(companion), 100);
    }

    function testMissingReceiverHookRollsBack() public {
        NonReceiver receiver = new NonReceiver();
        vm.expectRevert(
            abi.encodeWithSelector(IERC721Errors.ERC721InvalidReceiver.selector, address(receiver))
        );
        receiver.claim(companion);
        assertEq(companion.totalSupply(), 99);
        assertFalse(companion.hasMinted(address(receiver)));
    }

    function testRevertingReceiverCannotBlockOtherMinters() public {
        RevertingReceiver receiver = new RevertingReceiver();
        vm.expectRevert(RevertingReceiver.ReceiverRefused.selector);
        receiver.claim(companion);
        assertEq(_mint(alice), 100);
        assertEq(companion.publicMinted(), 1);
    }

    function testCallbackTransferAndReentryCannotClaimTwice() public {
        ReentrantReceiver receiver = new ReentrantReceiver(companion, bob);
        assertEq(receiver.claim(), 100);
        assertFalse(receiver.reentered());
        assertEq(receiver.reentryError(), abi.encodeWithSelector(SqueekCompanion.AlreadyMinted.selector));
        assertEq(receiver.observedSupply(), 100);
        assertEq(receiver.observedMintBlock(), block.number);
        assertTrue(receiver.observedEligibility());
        assertEq(companion.ownerOf(100), bob);
        assertEq(companion.balanceOf(address(receiver)), 0);
        assertTrue(companion.hasMinted(address(receiver)));
        assertEq(companion.totalSupply(), 100);
    }

    function testMintDoesNotDependOnCoreAvailability() public {
        vm.etch(CORE, hex"");
        assertEq(_mint(alice), 100);
        vm.expectRevert();
        companion.tokenURI(100);
        vm.prank(alice);
        companion.transferFrom(alice, bob, 100);
        assertEq(companion.ownerOf(100), bob);
    }

    function testUnauthorizedReserveTransferRejected() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, alice, 1));
        companion.transferFrom(RESERVE, alice, 1);
    }

    function testReserveOwnerMayTransferTheirTokens() public {
        vm.prank(RESERVE);
        companion.transferFrom(RESERVE, alice, 99);
        assertEq(companion.ownerOf(99), alice);
        assertEq(companion.balanceOf(RESERVE), 98);
        assertEq(companion.publicMinted(), 0);
        assertEq(companion.mintBlock(99), 20_000_000);
    }

    function testNoOwnerMintPauseOrUpgradeBackdoors() public {
        bytes[4] memory calls = [
            abi.encodeWithSignature("reserveMint(address,uint256)", RESERVE, 1),
            abi.encodeWithSignature("pause()"),
            abi.encodeWithSignature("setCore(address)", alice),
            abi.encodeWithSignature("upgradeTo(address)", alice)
        ];
        for (uint256 i; i < calls.length; ++i) {
            vm.prank(RESERVE);
            (bool success,) = address(companion).call(calls[i]);
            assertFalse(success);
        }
        assertEq(companion.totalSupply(), 99);
    }

    function testFuzzDistinctWalletsReceiveDistinctPublicTokens(uint8 rawCount) public {
        uint256 count = bound(rawCount, 1, 32);
        for (uint256 i; i < count; ++i) {
            address claimant = address(uint160(0x20000 + i));
            uint256 tokenId = _mint(claimant);
            assertEq(tokenId, 100 + i);
            assertEq(companion.ownerOf(tokenId), claimant);
        }
        assertEq(companion.totalSupply(), 99 + count);
        assertEq(companion.balanceOf(RESERVE), 99);
    }
}

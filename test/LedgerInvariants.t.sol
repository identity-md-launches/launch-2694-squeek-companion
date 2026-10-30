// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {CompanionTestBase} from "./helpers/CompanionTestBase.sol";
import {CompanionLedgerHandler} from "./handlers/CompanionLedgerHandler.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

abstract contract LedgerInvariantBase is CompanionTestBase {
    CompanionLedgerHandler internal ledger;

    function _configure(uint256 seededClaims) internal {
        super.setUp();
        ledger = new CompanionLedgerHandler(companion, seededClaims);
        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = CompanionLedgerHandler.mint.selector;
        selectors[1] = CompanionLedgerHandler.approve.selector;
        selectors[2] = CompanionLedgerHandler.setOperator.selector;
        selectors[3] = CompanionLedgerHandler.transfer.selector;
        selectors[4] = CompanionLedgerHandler.roundTrip.selector;
        selectors[5] = CompanionLedgerHandler.attackReserve.selector;
        selectors[6] = CompanionLedgerHandler.mintWithValue.selector;
        targetContract(address(ledger));
        targetSelector(FuzzSelector({addr: address(ledger), selectors: selectors}));
        ledger.assertModel();
        ledger.assertEveryToken();
    }

    function invariant_independentLedgerMatchesEveryObservableBalanceAndAuthorization() public view {
        ledger.assertModel();
    }

    function invariant_noUncountedTokenExists() public {
        uint256 nextId = 100 + ledger.publicMints();
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, nextId));
        companion.ownerOf(nextId);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 0));
        companion.ownerOf(0);
    }

    function afterInvariant() public view {
        ledger.assertEveryToken();
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 64
/// forge-config: default.invariant.fail-on-revert = true
contract LedgerInvariantTest is LedgerInvariantBase {
    function setUp() public override {
        _configure(0);
    }
}

/// @notice Six slots remain at the start. Nine competing wallets can cross the public cap in random order.
/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 64
/// forge-config: default.invariant.fail-on-revert = true
contract NearCapLedgerInvariantTest is LedgerInvariantBase {
    function setUp() public override {
        _configure(894);
    }

    function testNearCapHandlerReachesExhaustionAndCannotRestoreEligibilityByTransfer() public {
        ledger.mint(8, 1, false); // rejected receiver leaves all six remaining slots available
        for (uint256 i; i < 5; ++i) {
            ledger.mint(i, 1, true);
        }
        ledger.mint(8, 1, true);
        assertEq(companion.publicMinted(), 900);
        assertEq(companion.totalSupply(), 999);
        ledger.mint(5, 1, true); // fresh wallet after exhaustion
        assertFalse(companion.hasMinted(ledger.actor(5)));
        ledger.transfer(1799, 8, 1, 1); // public token index 899: the receiver sends ID 999 away
        ledger.mint(8, 1, true); // lifetime claim remains consumed
        ledger.assertModel();
        ledger.assertEveryToken();
        assertEq(companion.ownerOf(999), ledger.actor(1));
        assertTrue(companion.hasMinted(ledger.actor(8)));
    }
}

/// @dev Deterministic sequences exercise paths that random scheduling might seldom reach.
contract LedgerHandlerSequencesTest is CompanionTestBase {
    CompanionLedgerHandler private ledger;

    function setUp() public override {
        super.setUp();
        ledger = new CompanionLedgerHandler(companion, 0);
    }

    function testRevokedTokenApprovalCannotBeUsedAfterSelfTransfer() public {
        ledger.mint(1, 1, true);
        ledger.approve(1, 1, 2, true, false); // tokenSeed 1 selects public ID 100
        ledger.transfer(1, 1, 1, 1 | 64); // owner self-transfer clears the approval
        ledger.transfer(1, 2, 3, 0); // former delegate is now unauthorized
        ledger.assertModel();
        assertEq(companion.ownerOf(100), ledger.actor(1));
        assertEq(companion.getApproved(100), address(0));
    }

    function testOperatorCanApproveButTokenDelegateCannotRedelegate() public {
        ledger.mint(1, 1, true);
        ledger.setOperator(1, 2, true, false);
        ledger.approve(1, 2, 3, false, false);
        ledger.approve(1, 3, 4, false, false); // token delegate has transfer rights only
        ledger.transfer(1, 3, 4, 0);
        ledger.transfer(1, 2, 2, 0); // previous owner's operator cannot seize the token
        ledger.assertModel();
        assertEq(companion.ownerOf(100), ledger.actor(4));
    }

    function testRevokedOperatorAndRejectingSafeTransferLeaveLedgerIntact() public {
        ledger.mint(1, 1, true);
        ledger.setOperator(1, 2, true, false);
        ledger.setOperator(1, 2, false, false);
        ledger.transfer(1, 2, 3, 0);
        ledger.approve(1, 1, 2, true, false);
        ledger.transfer(1, 2, 8, 4); // approved caller; rejecting contract receiver
        ledger.assertModel();
        assertEq(companion.ownerOf(100), ledger.actor(1));
        assertEq(companion.getApproved(100), ledger.actor(2));
        ledger.transfer(1, 2, 8, 4 | 16); // receiver now accepts
        ledger.assertModel();
        assertEq(companion.ownerOf(100), ledger.actor(8));
    }

    function testReserveMovesOnlyWithItsHoldersAuthorization() public {
        ledger.attackReserve(99, 2);
        ledger.setOperator(0, 2, true, false);
        ledger.attackReserve(99, 2);
        ledger.mint(2, 1, true); // transferred reserve did not consume a public claim
        ledger.assertModel();
        assertEq(companion.ownerOf(99), ledger.actor(2));
        assertEq(companion.publicMinted(), 1);
        assertEq(companion.balanceOf(RESERVE), 98);
    }
}

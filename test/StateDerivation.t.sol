// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {CompanionTestBase, CompanionArt, ISqueekCore, SqueekCompanion} from "./helpers/CompanionTestBase.sol";
import {MockSqueekCore} from "./mocks/MockSqueekCore.sol";

contract StateDerivationTest is CompanionTestBase {
    function testRunningAtFrontier() public {
        _single(100, 100, 1, 42_999_999_999, 500);
        _assertActivity(CompanionArt.HamsterState.RUNNING);
    }

    function testRunningAtOldestOfThreeRounds() public {
        _single(100, 98, 1, 0, 500);
        _assertActivity(CompanionArt.HamsterState.RUNNING);
    }

    function testNappingJustOutsideThreeRounds() public {
        _single(100, 97, 1, 0, 500);
        _assertActivity(CompanionArt.HamsterState.NAPPING);
    }

    function testNappingAtOldestOfTwelveRounds() public {
        _single(100, 89, 1, 0, 500);
        _assertActivity(CompanionArt.HamsterState.NAPPING);
    }

    function testSleepingAtExclusiveTwelveRoundBoundary() public {
        _single(100, 88, 100, 0, 500);
        _assertActivity(CompanionArt.HamsterState.SLEEPING);
    }

    function testSleepingWithoutAnyActiveRoundsDespiteHistoricalWork() public {
        _empty(100, 55_000_000_000, 500);
        _assertActivity(CompanionArt.HamsterState.SLEEPING);
    }

    function testZeroWorkCheckpointIsNotActivity() public {
        _single(100, 100, 0, 0, 500);
        _assertActivity(CompanionArt.HamsterState.SLEEPING);
    }

    function testZeroWorkRecentCheckpointDoesNotOverrideNapping() public {
        uint64[] memory ids = new uint64[](2);
        uint64[] memory works = new uint64[](2);
        ids[0] = 90;
        ids[1] = 100;
        works[0] = 9;
        core.setHistory(100, 0, 500, ids, works);
        _assertActivity(CompanionArt.HamsterState.NAPPING);
    }

    function testAllTwelveActiveRoundsFitOnePageAndRecentWins() public {
        uint64[] memory ids = new uint64[](12);
        uint64[] memory works = new uint64[](12);
        for (uint64 i; i < 12; ++i) {
            ids[i] = 89 + i;
            works[i] = 1;
        }
        core.setHistory(100, 0, 500, ids, works);
        vm.expectCall(CORE, abi.encodeCall(ISqueekCore.roundPage, (88, 100, 16)), 1);
        _assertActivity(CompanionArt.HamsterState.RUNNING);
    }

    function testGenesisFrontierZeroUsesValidEmptyPage() public {
        _empty(0, 0, 0);
        vm.expectCall(CORE, abi.encodeCall(ISqueekCore.roundPage, (0, 0, 16)), 1);
        _assertActivity(CompanionArt.HamsterState.SLEEPING);
    }

    function testFirstRoundIsRunning() public {
        _single(1, 1, 1, 0, 0);
        vm.expectCall(CORE, abi.encodeCall(ISqueekCore.roundPage, (0, 1, 16)), 1);
        _assertActivity(CompanionArt.HamsterState.RUNNING);
    }

    function testFrontierThreeIncludesRoundOne() public {
        _single(3, 1, 1, 0, 0);
        _assertActivity(CompanionArt.HamsterState.RUNNING);
    }

    function testFrontierFourRoundOneIsNapping() public {
        _single(4, 1, 1, 0, 0);
        _assertActivity(CompanionArt.HamsterState.NAPPING);
    }

    function testFrontierTwelveIncludesRoundOne() public {
        _single(12, 1, 1, 0, 0);
        vm.expectCall(CORE, abi.encodeCall(ISqueekCore.roundPage, (0, 12, 16)), 1);
        _assertActivity(CompanionArt.HamsterState.NAPPING);
    }

    function testFrontierThirteenExcludesRoundOne() public {
        _single(13, 1, 1, 0, 0);
        vm.expectCall(CORE, abi.encodeCall(ISqueekCore.roundPage, (1, 13, 16)), 1);
        _assertActivity(CompanionArt.HamsterState.SLEEPING);
    }

    function testMaximumFrontierDoesNotOverflow() public {
        _single(type(uint64).max, type(uint64).max, 1, type(uint96).max, 0);
        (CompanionArt.HamsterState activity, uint256 height, uint64 frontier) = companion.currentState();
        assertEq(uint256(activity), uint256(CompanionArt.HamsterState.RUNNING));
        assertEq(height, uint256(type(uint96).max) / 1e9);
        assertEq(frontier, type(uint64).max);
    }

    function testHeightComesFromBlockUnitsNotWorkOrReportedHeight() public {
        _single(100, 100, 10, 42_999_999_999, 1234);
        core.setReportedHeight(999);
        (, uint256 height,) = companion.currentState();
        assertEq(height, 42);
    }

    function testPausedCoreKeepsLastSettledActivity() public {
        _single(100, 100, 1, 0, 0);
        core.setPaused(true);
        vm.warp(10_000_000_000);
        _assertActivity(CompanionArt.HamsterState.RUNNING);
    }

    function testStateFailurePropagates() public {
        vm.mockCallRevert(
            CORE, abi.encodeCall(ISqueekCore.state, ()), abi.encodeWithSignature("DependencyUnavailable()")
        );
        vm.expectRevert(abi.encodeWithSignature("DependencyUnavailable()"));
        companion.currentState();
    }

    function testPageFailurePropagates() public {
        vm.mockCallRevert(
            CORE,
            abi.encodeCall(ISqueekCore.roundPage, (88, 100, 16)),
            abi.encodeWithSignature("DependencyUnavailable()")
        );
        vm.expectRevert(abi.encodeWithSignature("DependencyUnavailable()"));
        companion.currentState();
    }

    function testNoCoreCodeRevertsInsteadOfInventingSleep() public {
        vm.etch(CORE, hex"");
        vm.expectRevert();
        companion.currentState();
    }

    function testIncompletePageRejected() public {
        ISqueekCore.RoundPage memory page = core.roundPage(88, 100, 16);
        page.certifiedThroughRound = 99;
        _expectInvalidPage(page);
    }

    function testReversedWorkRejected() public {
        _single(100, 100, 1, 0, 500);
        ISqueekCore.RoundPage memory page = core.roundPage(88, 100, 16);
        page.rounds[0].cumulativeWork = 499;
        _expectInvalidPage(page);
    }

    function testOutOfRangeRoundRejected() public {
        _single(100, 100, 1, 0, 0);
        ISqueekCore.RoundPage memory page = core.roundPage(88, 100, 16);
        page.rounds[0].roundId = 101;
        _expectInvalidPage(page);
    }

    function testRoundAtExclusiveStartRejected() public {
        _single(100, 100, 1, 0, 0);
        ISqueekCore.RoundPage memory page = core.roundPage(88, 100, 16);
        page.rounds[0].roundId = 88;
        _expectInvalidPage(page);
    }

    function testUnsortedRoundsRejected() public {
        _single(100, 100, 1, 0, 0);
        ISqueekCore.RoundPage memory page = core.roundPage(88, 100, 16);
        ISqueekCore.RoundCheckpoint memory checkpoint = page.rounds[0];
        page.rounds = new ISqueekCore.RoundCheckpoint[](2);
        page.rounds[0] = checkpoint;
        checkpoint.roundId = 99;
        page.rounds[1] = checkpoint;
        _expectInvalidPage(page);
    }

    function testOversizedPageRejected() public {
        ISqueekCore.RoundPage memory page = core.roundPage(88, 100, 16);
        page.rounds = new ISqueekCore.RoundCheckpoint[](17);
        _expectInvalidPage(page);
    }

    function testPageEndpointMismatchRejected() public {
        ISqueekCore.RoundPage memory page = core.roundPage(88, 100, 16);
        page.end.cumulativeWork = 1;
        _expectInvalidPage(page);
    }

    function testStateAndPageMismatchRejected() public {
        ISqueekCore.RoundPage memory page = core.roundPage(88, 100, 16);
        page.start.cumulativeWork = 1;
        page.end.cumulativeWork = 1;
        _expectInvalidPage(page);
    }

    function testMockRejectsActualInvalidBounds() public {
        vm.expectRevert(MockSqueekCore.InvalidRoundPageBounds.selector);
        core.roundPage(90, 89, 16);
        vm.expectRevert(MockSqueekCore.InvalidRoundPageBounds.selector);
        core.roundPage(0, 101, 16);
        vm.expectRevert(MockSqueekCore.InvalidRoundPageBounds.selector);
        core.roundPage(0, 100, 17);
    }

    function testMockHonorsTruncatedPageFrontier() public {
        _single(100, 98, 1, 0, 0);
        ISqueekCore.RoundPage memory page = core.roundPage(88, 100, 0);
        assertEq(page.certifiedThroughRound, 97);
        assertEq(page.rounds.length, 0);
    }

    function testFuzzSmallFrontierBounds(uint8 rawFrontier) public {
        uint64 frontier = uint64(bound(rawFrontier, 0, 12));
        _empty(frontier, 0, 0);
        vm.expectCall(CORE, abi.encodeCall(ISqueekCore.roundPage, (0, frontier, 16)), 1);
        _assertActivity(CompanionArt.HamsterState.SLEEPING);
    }

    function testFuzzHeightDivision(uint96 units) public {
        _empty(0, units, 0);
        (, uint256 height,) = companion.currentState();
        assertEq(height, uint256(units) / 1_000_000_000);
    }

    function testFuzzSingleActivityWindow(uint64 rawFrontier, uint64 rawRound, uint64 rawWork) public {
        uint64 frontier = uint64(bound(rawFrontier, 1, type(uint64).max));
        uint64 roundId = uint64(bound(rawRound, 1, frontier));
        _single(frontier, roundId, rawWork, 0, 0);
        CompanionArt.HamsterState expected = CompanionArt.HamsterState.SLEEPING;
        if (rawWork > 0 && frontier - roundId < 12) {
            expected = frontier - roundId < 3
                ? CompanionArt.HamsterState.RUNNING
                : CompanionArt.HamsterState.NAPPING;
        }
        _assertActivity(expected);
    }

    function testFuzzSparseHistoryMatchesIndependentWindowModel(uint16 activityBits, uint64 rawFrontier)
        public
    {
        uint64 frontier = uint64(bound(rawFrontier, 16, type(uint64).max));
        uint64[] memory ids = new uint64[](16);
        uint64[] memory work = new uint64[](16);
        bool recent;
        bool older;
        for (uint64 i; i < 16; ++i) {
            ids[i] = frontier - 15 + i;
            work[i] = (activityBits >> i) & 1;
            if (work[i] > 0 && i >= 13) recent = true;
            if (work[i] > 0 && i >= 4) older = true;
        }
        core.setHistory(frontier, 0, 9876, ids, work);
        _assertActivity(
            recent
                ? CompanionArt.HamsterState.RUNNING
                : older ? CompanionArt.HamsterState.NAPPING : CompanionArt.HamsterState.SLEEPING
        );
    }

    function _expectInvalidPage(ISqueekCore.RoundPage memory page) private {
        vm.mockCall(CORE, abi.encodeCall(ISqueekCore.roundPage, (88, 100, 16)), abi.encode(page));
        vm.expectRevert(SqueekCompanion.InvalidCorePage.selector);
        companion.currentState();
    }
}

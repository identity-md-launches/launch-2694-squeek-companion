// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {CompanionTestBase, CompanionArt, ISqueekCore, SqueekCompanion} from "./helpers/CompanionTestBase.sol";
import {DataUri} from "./helpers/DataUri.sol";

/// @notice Properties of the observed history, independently of how the collection scans its page.
/// forge-config: default.fuzz.runs = 1000
contract ActivityPropertiesTest is CompanionTestBase {
    function testFuzzTranslatingHistoryAndScalingPositiveWorkPreservesActivity(
        uint16 active,
        uint64 rawShift,
        uint32 rawScale,
        uint32 baseline
    ) public {
        uint64[] memory rounds = new uint64[](16);
        uint64[] memory work = new uint64[](16);
        for (uint64 i; i < 16; ++i) {
            rounds[i] = i + 1;
            work[i] = (active >> i) & 1;
        }
        core.setHistory(16, 7_000_000_001, 0, rounds, work);
        (CompanionArt.HamsterState original, uint256 originalHeight,) = companion.currentState();

        uint64 shift = uint64(bound(rawShift, 0, type(uint64).max - 16));
        uint64 scale = uint64(bound(rawScale, 1, type(uint32).max));
        for (uint256 i; i < 16; ++i) {
            rounds[i] += shift;
            work[i] *= scale;
        }
        core.setHistory(16 + shift, 7_000_000_001, baseline, rounds, work);
        (CompanionArt.HamsterState translated, uint256 height, uint64 frontier) = companion.currentState();
        assertEq(uint256(translated), uint256(original), "only ages and positive work matter");
        assertEq(height, originalHeight);
        assertEq(frontier, 16 + shift);
    }

    function testFuzzOneObservationAgesAndNewWorkWakesIt(uint64 rawRound, uint64 rawWork) public {
        uint64 activeRound = uint64(bound(rawRound, 1, type(uint64).max - 13));
        uint64 work = uint64(bound(rawWork, 1, type(uint64).max - 1));
        uint64[5] memory ages = [uint64(0), 2, 3, 11, 12];
        CompanionArt.HamsterState[5] memory expected = [
            CompanionArt.HamsterState.RUNNING,
            CompanionArt.HamsterState.RUNNING,
            CompanionArt.HamsterState.NAPPING,
            CompanionArt.HamsterState.NAPPING,
            CompanionArt.HamsterState.SLEEPING
        ];
        for (uint256 i; i < ages.length; ++i) {
            _single(activeRound + ages[i], activeRound, work, 9_000_000_001, 0);
            _assertActivity(expected[i]);
        }
        uint64[] memory rounds = new uint64[](2);
        uint64[] memory works = new uint64[](2);
        rounds[0] = activeRound;
        rounds[1] = activeRound + 13;
        works[0] = work;
        works[1] = 1;
        core.setHistory(activeRound + 13, 9_000_000_002, 0, rounds, works);
        _assertActivity(CompanionArt.HamsterState.RUNNING);
    }

    function testFuzzHeightIsFloorAndAddingOneBlockAddsExactlyOne(uint96 rawUnits) public {
        uint96 units = uint96(bound(rawUnits, 0, type(uint96).max - 1_000_000_000));
        _empty(0, units, 0);
        (, uint256 height,) = companion.currentState();
        assertLe(height * 1_000_000_000, uint256(units));
        assertLt(uint256(units), (height + 1) * 1_000_000_000);
        _empty(0, units + 1_000_000_000, 0);
        (CompanionArt.HamsterState stateAfter, uint256 nextHeight,) = companion.currentState();
        assertEq(nextHeight, height + 1);
        assertEq(uint256(stateAfter), uint256(CompanionArt.HamsterState.SLEEPING));
    }

    function testLastUnitOfCumulativeWorkCountsAsActivity() public {
        _single(type(uint64).max, type(uint64).max, 1, 0, type(uint64).max - 1);
        _assertActivity(CompanionArt.HamsterState.RUNNING);
        _single(type(uint64).max, type(uint64).max - 3, 1, 0, type(uint64).max - 1);
        _assertActivity(CompanionArt.HamsterState.NAPPING);
    }

    function testMaximumHistoricalWorkWithZeroRecentDeltaIsSleeping() public {
        _single(type(uint64).max, type(uint64).max, 0, type(uint96).max, type(uint64).max);
        _assertActivity(CompanionArt.HamsterState.SLEEPING);
    }

    function testAddingZeroWorkCheckpointsDoesNotEraseRecentActivity() public {
        uint64[] memory rounds = new uint64[](3);
        uint64[] memory works = new uint64[](3);
        rounds[0] = 98;
        rounds[1] = 99;
        rounds[2] = 100;
        works[0] = 1;
        core.setHistory(100, 42, type(uint64).max - 1, rounds, works);
        _assertActivity(CompanionArt.HamsterState.RUNNING);
    }

    function testInvalidCheckpointAfterRunningCheckpointStillReverts() public {
        ISqueekCore.RoundPage memory page = _twoRecentCheckpoints();
        // A scanner must validate the rest of the page even after it already found RUNNING.
        page.rounds[1].cumulativeWork = page.rounds[0].cumulativeWork - 1;
        _assertInvalidForStateAndMetadata(page);
    }

    function testDuplicateCheckpointAfterRunningCheckpointReverts() public {
        ISqueekCore.RoundPage memory page = _twoRecentCheckpoints();
        page.rounds[1].roundId = page.rounds[0].roundId;
        _assertInvalidForStateAndMetadata(page);
    }

    function testFutureCheckpointAfterRunningCheckpointReverts() public {
        ISqueekCore.RoundPage memory page = _twoRecentCheckpoints();
        page.rounds[1].roundId = 101;
        _assertInvalidForStateAndMetadata(page);
    }

    function testEndpointMismatchAfterRunningCheckpointReverts() public {
        ISqueekCore.RoundPage memory page = _twoRecentCheckpoints();
        ++page.end.cumulativeWork;
        _assertInvalidForStateAndMetadata(page);
    }

    function testOverCertifiedPageReverts() public {
        ISqueekCore.RoundPage memory page = _twoRecentCheckpoints();
        page.certifiedThroughRound = 101;
        _assertInvalidForStateAndMetadata(page);
    }

    function testFuzzTruncatedStateResponseCannotProduceMetadata(uint8 length) public {
        // Every proper prefix is shorter than the eight static ABI words required by state().
        bytes memory encoded = abi.encode(core.state());
        bytes memory truncated = new bytes(length);
        for (uint256 i; i < length; ++i) {
            truncated[i] = encoded[i];
        }
        vm.mockCall(CORE, abi.encodeCall(ISqueekCore.state, ()), truncated);
        vm.expectRevert();
        companion.currentState();
        vm.expectRevert();
        companion.tokenURI(1);
    }

    function testTruncatedDynamicPageResponseCannotProduceMetadata() public {
        bytes memory encoded = abi.encode(_twoRecentCheckpoints());
        bytes memory truncated = new bytes(encoded.length - 1);
        for (uint256 i; i < truncated.length; ++i) {
            truncated[i] = encoded[i];
        }
        vm.mockCall(CORE, abi.encodeCall(ISqueekCore.roundPage, (88, 100, 16)), truncated);
        vm.expectRevert();
        companion.currentState();
        vm.expectRevert();
        companion.tokenURI(1);
    }

    function testMetadataRecoversAfterDependencyFailureWithoutCollectionWrite() public {
        _single(100, 100, 1, 42_000_000_000, 0);
        string memory beforeFailure = companion.tokenURI(99);
        vm.mockCallRevert(CORE, abi.encodeCall(ISqueekCore.state, ()), hex"12345678");
        vm.expectRevert(bytes4(0x12345678));
        companion.tokenURI(99);
        vm.clearMockedCalls();
        assertEq(companion.tokenURI(99), beforeFailure);

        _single(112, 100, 1, 42_000_000_000, 0);
        string memory json = DataUri.decode(companion.tokenURI(99), "data:application/json;base64,");
        assertEq(vm.parseJsonString(json, ".attributes[0].value"), "SLEEPING");
        assertEq(vm.parseJsonUint(json, ".attributes[2].value"), 20_000_000);
        assertEq(companion.totalSupply(), 99);
    }

    function _twoRecentCheckpoints() private returns (ISqueekCore.RoundPage memory) {
        uint64[] memory rounds = new uint64[](2);
        uint64[] memory work = new uint64[](2);
        rounds[0] = 98;
        rounds[1] = 100;
        work[0] = 2;
        work[1] = 3;
        core.setHistory(100, 42_000_000_000, 10, rounds, work);
        return core.roundPage(88, 100, 16);
    }

    function _assertInvalidForStateAndMetadata(ISqueekCore.RoundPage memory page) private {
        vm.mockCall(CORE, abi.encodeCall(ISqueekCore.roundPage, (88, 100, 16)), abi.encode(page));
        vm.expectRevert(SqueekCompanion.InvalidCorePage.selector);
        companion.currentState();
        vm.expectRevert(SqueekCompanion.InvalidCorePage.selector);
        companion.tokenURI(1);
        assertEq(companion.ownerOf(1), RESERVE);
    }
}

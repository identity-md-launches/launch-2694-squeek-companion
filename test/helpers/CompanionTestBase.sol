// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {SqueekCompanion} from "../../src/SqueekCompanion.sol";
import {ISqueekCore} from "../../src/interfaces/ISqueekCore.sol";
import {CompanionArt} from "../../src/libraries/CompanionArt.sol";
import {MockSqueekCore} from "../mocks/MockSqueekCore.sol";

abstract contract CompanionTestBase is Test {
    address internal constant CORE = 0x74665dAecA35A2303e767E76a2FF1FB6F93e119f;
    address internal constant RESERVE = 0x3C7838665Ff8215c95500E1a6306e19E146674a0;
    SqueekCompanion internal companion;
    MockSqueekCore internal core;
    address internal alice;
    address internal bob;

    function setUp() public virtual {
        vm.chainId(11155111);
        vm.roll(20_000_000);
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        // The production contract always uses the actual proxy address; only tests install a mock there.
        MockSqueekCore implementation = new MockSqueekCore();
        vm.etch(CORE, address(implementation).code);
        core = MockSqueekCore(CORE);
        _empty(100, 42_123_456_789, 0);
        companion = new SqueekCompanion();
    }

    function _empty(uint64 frontier, uint96 units, uint64 baseline) internal {
        core.setHistory(frontier, units, baseline, new uint64[](0), new uint64[](0));
    }

    function _single(uint64 frontier, uint64 roundId, uint64 work, uint96 units, uint64 baseline) internal {
        uint64[] memory ids = new uint64[](1);
        uint64[] memory works = new uint64[](1);
        ids[0] = roundId;
        works[0] = work;
        core.setHistory(frontier, units, baseline, ids, works);
    }

    function _mint(address caller) internal returns (uint256) {
        vm.prank(caller);
        return companion.mint();
    }

    function _assertActivity(CompanionArt.HamsterState expected) internal view {
        (CompanionArt.HamsterState activity,,) = companion.currentState();
        assertEq(uint256(activity), uint256(expected));
    }
}

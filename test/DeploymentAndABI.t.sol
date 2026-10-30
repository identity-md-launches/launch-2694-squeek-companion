// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {CompanionTestBase, CompanionArt, ISqueekCore} from "./helpers/CompanionTestBase.sol";

contract DeploymentAndABITest is CompanionTestBase {
    /// @dev Hand-encoded return words from the published v3 tuple layout, independent of mock structs.
    function testPublishedV3AbiDecodesExactFieldWidthsAndNestedPageOffsets() public {
        assertEq(ISqueekCore.state.selector, bytes4(keccak256("state()")));
        assertEq(ISqueekCore.roundPage.selector, bytes4(keccak256("roundPage(uint64,uint64,uint256)")));
        vm.mockCall(
            CORE,
            abi.encodeWithSignature("state()"),
            abi.encode(
                uint64(100),
                uint64(124),
                uint96(42_500_000_000),
                uint64(42),
                uint96(500_000_000),
                uint32(4567),
                uint256(99),
                true
            )
        );
        vm.mockCall(
            CORE,
            abi.encodeWithSignature("roundPage(uint64,uint64,uint256)", uint64(88), uint64(100), uint256(16)),
            bytes.concat(
                abi.encode(
                    uint256(32), // offset to the single dynamic RoundPage return tuple
                    uint64(100), // certifiedThroughRound
                    uint64(123),
                    uint96(9_000_000_000),
                    uint32(4321), // start
                    uint64(124),
                    uint96(42_500_000_000),
                    uint32(4567), // end
                    uint256(256) // rounds offset relative to the tuple's beginning (8 words)
                ),
                abi.encode(
                    uint256(1), // array length
                    uint64(99),
                    uint64(124),
                    uint96(42_500_000_000),
                    uint32(4567),
                    bytes32(uint256(1))
                )
            )
        );
        (CompanionArt.HamsterState activity, uint256 height, uint64 frontier) = companion.currentState();
        assertEq(uint256(activity), uint256(CompanionArt.HamsterState.RUNNING));
        assertEq(height, 42);
        assertEq(frontier, 100);
    }

    function testRuntimeFitsEip170AndContainsNoReachableEscapeOpcodes() public view {
        bytes memory code = address(companion).code;
        assertGt(code.length, 0);
        assertLe(code.length, 24_576);
        bool reachable = true;
        for (uint256 j; j < code.length; ++j) {
            uint8 op = uint8(code[j]);
            if (op == 0x5b) reachable = true;
            if (op >= 0x60 && op <= 0x7f) {
                j += op - 0x5f;
                continue;
            }
            if (reachable) assertTrue(op != 0xf4 && op != 0xf2 && op != 0xff, "forbidden runtime opcode");
            if (op == 0x00 || op == 0x56 || op == 0xf3 || op == 0xfd || op == 0xfe || op == 0xff) {
                reachable = false;
            }
        }
    }
}

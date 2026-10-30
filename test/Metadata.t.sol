// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {console2} from "forge-std/console2.sol";
import {CompanionTestBase, CompanionArt} from "./helpers/CompanionTestBase.sol";
import {DataUri} from "./helpers/DataUri.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract MetadataTest is CompanionTestBase {
    function testJsonAndSvgAreValidDataUrisWithRequiredFields() public {
        uint256 id = _mint(alice);
        _single(100, 100, 7, 42_999_999_999, 1000);
        (string memory json, string memory svg) = _decoded(id);
        assertEq(vm.parseJsonString(json, ".name"), "_Squeek Companion #100");
        assertGt(bytes(vm.parseJsonString(json, ".description")).length, 0);
        _assertTraits(json, "RUNNING", 42, 20_000_000);
        assertTrue(vm.contains(svg, '<svg xmlns="http://www.w3.org/2000/svg"'));
        assertTrue(vm.contains(svg, 'id="open-eyes"'));
        assertTrue(vm.contains(svg, 'id="motion-lines"'));
        assertTrue(vm.contains(svg, 'fill="#f8d99c"'));
        assertTrue(vm.contains(svg, ">42</text>"));
        assertFalse(vm.contains(svg, 'id="closed-eyes"'));
    }

    function testNappingArtHasClosedEyesZzzAndNightBackground() public {
        uint256 id = _mint(alice);
        _single(100, 97, 7, 42_000_000_000, 1000);
        (string memory json, string memory svg) = _decoded(id);
        _assertTraits(json, "NAPPING", 42, 20_000_000);
        assertTrue(vm.contains(svg, 'id="closed-eyes"'));
        assertTrue(vm.contains(svg, 'id="zzz"'));
        assertTrue(vm.contains(svg, 'fill="#24365b"'));
        assertFalse(vm.contains(svg, 'id="motion-lines"'));
        assertFalse(vm.contains(svg, 'id="moon"'));
    }

    function testSleepingArtHasMoonAndDeeperNightBackground() public {
        uint256 id = _mint(alice);
        (string memory json, string memory svg) = _decoded(id);
        _assertTraits(json, "SLEEPING", 42, 20_000_000);
        assertTrue(vm.contains(svg, 'id="closed-eyes"'));
        assertTrue(vm.contains(svg, 'id="moon"'));
        assertTrue(vm.contains(svg, 'fill="#10172e"'));
        assertFalse(vm.contains(svg, 'id="motion-lines"'));
    }

    function testMetadataChangesLiveWhileMintBlockStaysFixedAcrossTransfer() public {
        uint256 id = _mint(alice);
        _single(100, 100, 1, 42_000_000_000, 0);
        string memory running = companion.tokenURI(id);
        _single(103, 100, 1, 43_000_000_000, 0);
        vm.roll(20_999_999);
        vm.prank(alice);
        companion.transferFrom(alice, bob, id);
        string memory napping = companion.tokenURI(id);
        (string memory json,) = _decoded(id);
        _assertTraits(json, "NAPPING", 43, 20_000_000);
        _single(112, 100, 1, 43_000_000_000, 0);
        string memory sleeping = companion.tokenURI(id);
        (json,) = _decoded(id);
        _assertTraits(json, "SLEEPING", 43, 20_000_000);
        assertNotEq(running, napping);
        assertNotEq(napping, sleeping);
        assertNotEq(sleeping, running);
        assertEq(companion.mintBlock(id), 20_000_000);
    }

    function testBlockOverlayChangesEvenWithinSameActivityState() public {
        uint256 id = _mint(alice);
        _single(100, 100, 1, 999_999_999, 0);
        (, string memory beforeSvg) = _decoded(id);
        _single(100, 100, 1, 1_000_000_000, 0);
        (string memory json, string memory afterSvg) = _decoded(id);
        _assertTraits(json, "RUNNING", 1, 20_000_000);
        assertTrue(vm.contains(beforeSvg, ">0</text>"));
        assertTrue(vm.contains(afterSvg, ">1</text>"));
        assertNotEq(beforeSvg, afterSvg);
    }

    function testUnchangedCoreProducesIdenticalMetadataRegardlessOfTime() public {
        uint256 id = _mint(alice);
        string memory beforeUri = companion.tokenURI(id);
        vm.warp(10_000_000_000);
        vm.roll(30_000_000);
        assertEq(companion.tokenURI(id), beforeUri);
    }

    function testReserveTokenMetadataAvailableWithoutPublicMint() public view {
        (string memory json,) = _decoded(99);
        assertEq(vm.parseJsonString(json, ".name"), "_Squeek Companion #99");
        _assertTraits(json, "SLEEPING", 42, 20_000_000);
    }

    function testUnknownTokenRevertsBeforeDependencyRead() public {
        vm.etch(CORE, hex"");
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 100));
        companion.tokenURI(100);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 0));
        companion.tokenURI(0);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 1000));
        companion.mintBlock(1000);
    }

    function testFuzzMetadataPreservesNumericHeightsAndMintBlocks(uint96 units, uint64 mintAt) public {
        vm.roll(mintAt);
        uint256 id = _mint(alice);
        _empty(0, units, 0);
        (string memory json, string memory svg) = _decoded(id);
        _assertTraits(json, "SLEEPING", uint256(units) / 1e9, mintAt);
        assertTrue(vm.contains(svg, string.concat(">", vm.toString(uint256(units) / 1e9), "</text>")));
    }

    /// @dev scripts/export_artifacts.py captures these actual tokenURI outputs and validates JSON/XML.
    function testPreviewMetadata() public {
        uint256 id = _mint(alice);
        _single(100, 100, 1, 42_123_456_789, 0);
        console2.log(string.concat("PREVIEW_RUNNING=", companion.tokenURI(id)));
        _single(103, 100, 1, 42_123_456_789, 0);
        console2.log(string.concat("PREVIEW_NAPPING=", companion.tokenURI(id)));
        _single(112, 100, 1, 42_123_456_789, 0);
        console2.log(string.concat("PREVIEW_SLEEPING=", companion.tokenURI(id)));
        assertEq(companion.mintBlock(id), 20_000_000);
    }

    function _decoded(uint256 id) private view returns (string memory json, string memory svg) {
        json = DataUri.decode(companion.tokenURI(id), "data:application/json;base64,");
        svg = DataUri.decode(vm.parseJsonString(json, ".image"), "data:image/svg+xml;base64,");
    }

    function _assertTraits(string memory json, string memory state_, uint256 height, uint256 mintAt)
        private
        pure
    {
        assertEq(vm.parseJsonString(json, ".attributes[0].trait_type"), "state");
        assertEq(vm.parseJsonString(json, ".attributes[0].value"), state_);
        assertEq(vm.parseJsonString(json, ".attributes[1].trait_type"), "squeek_block");
        assertEq(vm.parseJsonString(json, ".attributes[1].display_type"), "number");
        assertEq(vm.parseJsonUint(json, ".attributes[1].value"), height);
        assertEq(vm.parseJsonString(json, ".attributes[2].trait_type"), "mint_block");
        assertEq(vm.parseJsonString(json, ".attributes[2].display_type"), "number");
        assertEq(vm.parseJsonUint(json, ".attributes[2].value"), mintAt);
    }
}

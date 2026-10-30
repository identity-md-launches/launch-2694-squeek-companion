// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ISqueekCore} from "./interfaces/ISqueekCore.sol";
import {CompanionArt} from "./libraries/CompanionArt.sol";

/// @title _Squeek Companion
/// @notice Immutable Sepolia ERC-721 reflecting SqueekCore's settled activity on every metadata read.
/// @dev No owner role, updater, upgrade path, external renderer, or constructor dependency calls.
contract SqueekCompanion is ERC721 {
    uint256 public constant MAX_SUPPLY = 999;
    uint256 public constant RESERVED_SUPPLY = 99;
    uint256 public constant PUBLIC_SUPPLY = MAX_SUPPLY - RESERVED_SUPPLY;
    uint256 public constant BLOCK_UNITS_PER_BLOCK = 1_000_000_000;
    uint64 public constant RUNNING_ROUNDS = 3;
    uint64 public constant LOOKBACK_ROUNDS = 12;
    uint256 public constant PAGE_RECORDS = 16;

    address public constant RESERVE_OWNER = 0x3C7838665Ff8215c95500E1a6306e19E146674a0;
    ISqueekCore public constant SQUEEK_CORE = ISqueekCore(0x74665dAecA35A2303e767E76a2FF1FB6F93e119f);

    uint256 public publicMinted;
    mapping(address wallet => bool minted) public hasMinted;
    mapping(uint256 tokenId => uint256 sepoliaBlock) private _mintBlocks;

    error AlreadyMinted();
    error PublicSupplyExhausted();
    error InvalidCorePage();

    constructor() ERC721("_Squeek Companion", "SQCOM") {
        // The fixed recipient is intentional. _mint performs no receiver hook or other external call.
        for (uint256 tokenId = 1; tokenId <= RESERVED_SUPPLY; ++tokenId) {
            _mintBlocks[tokenId] = block.number;
            _mint(RESERVE_OWNER, tokenId);
        }
    }

    /// @notice Claim one free public token per caller, for life. Sending ETH is rejected.
    /// @dev All mint accounting is committed before the ERC-721 receiver callback.
    function mint() external returns (uint256 tokenId) {
        if (hasMinted[msg.sender]) revert AlreadyMinted();
        if (publicMinted == PUBLIC_SUPPLY) revert PublicSupplyExhausted();
        hasMinted[msg.sender] = true;
        tokenId = RESERVED_SUPPLY + ++publicMinted;
        _mintBlocks[tokenId] = block.number;
        _safeMint(msg.sender, tokenId);
    }

    function totalSupply() external view returns (uint256) {
        return RESERVED_SUPPLY + publicMinted;
    }

    /// @notice Ethereum Sepolia block.number at mint, unchanged by transfers or SqueekCore activity.
    function mintBlock(uint256 tokenId) public view returns (uint256) {
        _requireOwned(tokenId);
        return _mintBlocks[tokenId];
    }

    /// @notice Returns activity (0 running, 1 napping, 2 sleeping), Squeek height, and settled frontier.
    /// @dev Bounds are (max(frontier - 12, 0), frontier]. No wall-clock extrapolation.
    ///      V3 checkpoints hold cumulative work; compare against the preceding checkpoint/start.
    ///      Dependency errors propagate, rather than misrepresenting unavailable data as sleep.
    function currentState()
        public
        view
        returns (CompanionArt.HamsterState activity, uint256 squeekBlock, uint64 frontier)
    {
        ISqueekCore.CoreState memory coreState = SQUEEK_CORE.state();
        frontier = coreState.settledThroughRound;
        squeekBlock = uint256(coreState.cumulativeBlockUnits) / BLOCK_UNITS_PER_BLOCK;
        uint64 afterRound = frontier > LOOKBACK_ROUNDS ? frontier - LOOKBACK_ROUNDS : 0;
        uint64 runningAfter = frontier > RUNNING_ROUNDS ? frontier - RUNNING_ROUNDS : 0;
        ISqueekCore.RoundPage memory page = SQUEEK_CORE.roundPage(afterRound, frontier, PAGE_RECORDS);

        // Twelve rounds fit in one sixteen-record page. An incomplete/malformed page is not silence.
        if (page.certifiedThroughRound != frontier || page.rounds.length > PAGE_RECORDS) {
            revert InvalidCorePage();
        }
        activity = CompanionArt.HamsterState.SLEEPING;
        uint64 previousRound = afterRound;
        uint64 previousWork = page.start.cumulativeWork;
        for (uint256 i; i < page.rounds.length; ++i) {
            ISqueekCore.RoundCheckpoint memory checkpoint = page.rounds[i];
            if (
                checkpoint.roundId <= previousRound || checkpoint.roundId > frontier
                    || checkpoint.cumulativeWork < previousWork
            ) revert InvalidCorePage();
            if (checkpoint.cumulativeWork > previousWork) {
                activity = checkpoint.roundId > runningAfter
                    ? CompanionArt.HamsterState.RUNNING
                    : CompanionArt.HamsterState.NAPPING;
            }
            previousRound = checkpoint.roundId;
            previousWork = checkpoint.cumulativeWork;
        }
        if (previousWork != page.end.cumulativeWork || page.end.cumulativeWork != coreState.cumulativeWork) {
            revert InvalidCorePage();
        }
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        (CompanionArt.HamsterState activity, uint256 squeekBlock,) = currentState();
        string memory image = string.concat(
            "data:image/svg+xml;base64,", Base64.encode(bytes(CompanionArt.render(activity, squeekBlock)))
        );
        string memory json = string.concat(
            '{"name":"_Squeek Companion #',
            Strings.toString(tokenId),
            '","description":"A companion reflecting Squeektoshi\'s settled on-chain wheel activity. ',
            'mint_block is the Sepolia block at mint. No rewards or upkeep.","image":"',
            image,
            '","attributes":[{"trait_type":"state","value":"',
            CompanionArt.stateName(activity),
            '"},{"display_type":"number","trait_type":"squeek_block","value":',
            Strings.toString(squeekBlock),
            '},{"display_type":"number","trait_type":"mint_block","value":',
            Strings.toString(_mintBlocks[tokenId]),
            "}]}"
        );
        return string.concat("data:application/json;base64,", Base64.encode(bytes(json)));
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ISqueekCore} from "../../src/interfaces/ISqueekCore.sol";

/// @dev Deterministic v3 ledger mock. Pagination uses an exclusive start, cumulative checkpoints,
///      and the real bounds/record-budget semantics. No network, clock or environment required.
contract MockSqueekCore is ISqueekCore {
    CoreState private _state;
    RoundCheckpoint[] private _checkpoints;
    uint64 private _baselineWork;

    error InvalidRoundPageBounds();

    function setHistory(
        uint64 frontier,
        uint96 units,
        uint64 baselineWork,
        uint64[] memory roundIds,
        uint64[] memory work
    ) external {
        require(roundIds.length == work.length, "length mismatch");
        delete _checkpoints;
        _baselineWork = baselineWork;
        uint64 cumulativeWork = baselineWork;
        uint64 previous;
        for (uint256 i; i < roundIds.length; ++i) {
            require(roundIds[i] > previous && roundIds[i] <= frontier, "bad history");
            cumulativeWork += work[i];
            _checkpoints.push(
                RoundCheckpoint(roundIds[i], cumulativeWork, units, 1000, bytes32(uint256(i + 1)))
            );
            previous = roundIds[i];
        }
        _state = CoreState(frontier, cumulativeWork, units, uint64(units / 1e9), units % 1e9, 1000, 7, false);
    }

    function setPaused(bool paused_) external {
        _state.paused = paused_;
    }

    function setReportedHeight(uint64 height) external {
        _state.blockHeight = height;
    }

    function state() external view returns (CoreState memory result) {
        return _state;
    }

    function roundPage(uint64 afterRound, uint64 throughRound, uint256 maxRecords)
        external
        view
        returns (RoundPage memory result)
    {
        if (afterRound > throughRound || throughRound > _state.settledThroughRound || maxRecords > 16) {
            revert InvalidRoundPageBounds();
        }
        result.certifiedThroughRound = throughRound;
        result.start = LedgerPosition(_baselineWork, 0, 1000);
        uint256 first;
        while (first < _checkpoints.length && _checkpoints[first].roundId <= afterRound) {
            result.start = _position(_checkpoints[first]);
            ++first;
        }
        uint256 count;
        while (first + count < _checkpoints.length && _checkpoints[first + count].roundId <= throughRound) {
            if (count == maxRecords) {
                result.certifiedThroughRound = _checkpoints[first + count].roundId - 1;
                break;
            }
            ++count;
        }
        result.rounds = new RoundCheckpoint[](count);
        result.end = result.start;
        for (uint256 i; i < count; ++i) {
            result.rounds[i] = _checkpoints[first + i];
            result.end = _position(result.rounds[i]);
        }
    }

    function _position(RoundCheckpoint memory checkpoint) private pure returns (LedgerPosition memory) {
        return LedgerPosition(
            checkpoint.cumulativeWork, checkpoint.cumulativeBlockUnits, checkpoint.workPerThousandBlocks
        );
    }
}

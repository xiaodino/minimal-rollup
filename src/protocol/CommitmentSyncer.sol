// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {LibSignal} from "../libs/LibSignal.sol";
import {LibTrieProof} from "../libs/LibTrieProof.sol";

import {ICheckpointTracker} from "./ICheckpointTracker.sol";
import {ICommitmentSyncer} from "./ICommitmentSyncer.sol";

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/// @dev Tracks and synchronizes commitments from different chains using their chainId.
abstract contract CommitmentSyncer is ICommitmentSyncer {
    using SafeCast for uint256;
    using LibSignal for bytes32;

    /// @dev The caller is not a recognized checkpoint tracker.
    error UnauthorizedCheckpointTracker();

    address private immutable _checkpointTracker;

    mapping(uint64 chainId => uint64) private _latestHeight;
    mapping(uint64 chainId => mapping(uint64 height => bytes32)) private _commitment;

    /// @dev Reverts if the caller is not the `checkpointTracker`.
    modifier onlyCheckpointTracker() {
        _checkCheckpointTracker(msg.sender);
        _;
    }

    /// @dev Sets the checkpoint tracker.
    constructor(address checkpointTracker_) {
        _checkpointTracker = checkpointTracker_;
    }

    /// @dev Contract that tracks commitment checkpoints.
    function checkpointTracker() public view virtual returns (ICheckpointTracker) {
        return ICheckpointTracker(_checkpointTracker);
    }

    /// @inheritdoc ICommitmentSyncer
    function commitmentId(uint64 chainId, uint64 height, bytes32 commitment) public pure virtual returns (bytes32 id) {
        return keccak256(abi.encodePacked(chainId, height, commitment));
    }

    /// @inheritdoc ICommitmentSyncer
    function verifyCommitment(uint64 chainId, uint64 height, bytes32 commitment, bytes32 root, bytes[] calldata proof)
        public
        view
        virtual
        returns (bool valid, bytes32 id)
    {
        id = commitmentId(chainId, height, commitment);
        return (LibTrieProof.verifyState(id.deriveSlot(), id, root, proof), id);
    }

    /// @inheritdoc ICommitmentSyncer
    function commitmentAt(uint64 chainId, uint64 height) public view virtual returns (bytes32 commitment) {
        return _commitment[chainId][height];
    }

    /// @inheritdoc ICommitmentSyncer
    function latestCommitment(uint64 chainId) public view virtual returns (bytes32 commitment) {
        return commitmentAt(chainId, latestHeight(chainId));
    }

    /// @inheritdoc ICommitmentSyncer
    function latestHeight(uint64 chainId) public view virtual returns (uint64 height) {
        return _latestHeight[chainId];
    }

    /// @inheritdoc ICommitmentSyncer
    function syncCommitment(uint64 chainId, uint64 height, bytes32 commitment, bytes32 root, bytes[] calldata proof)
        external
        virtual
        onlyCheckpointTracker
    {
        _checkCommitment(chainId, height, commitment, root, proof);
        _syncCommitment(chainId, height, commitment);
    }

    /// @dev Internal version of `syncCommitment` without access control.
    /// Emits `CommitmentSynced` if the provided `height` is larger than `latestHeight` for `chainId`.
    function _syncCommitment(bytes32 id, uint64 chainId, uint64 height, bytes32 commitment) internal virtual {
        if (latestHeight(chainId) < height) {
            _latestHeight[chainId] = height;
            _commitment[chainId][height] = commitment;
            // assert(id == commitmentId(chainId, height, commitment));
            id.signal();
            emit CommitmentSynced(chainId, height, commitment);
        }
    }

    /// @dev Reverts if the commitment is invalid.
    function _checkCommitment(uint64 chainId, uint64 height, bytes32 commitment, bytes32 root, bytes[] calldata proof)
        internal
        virtual
        returns (bytes32 id)
    {
        bool valid;
        (valid, id) = verifyCommitment(chainId, height, commitment, root, proof);
        require(valid, InvalidCommitment());
    }

    /// @dev Must revert if the caller is not an authorized syncer.
    function _checkCheckpointTracker(address caller) internal virtual {
        require(caller == address(checkpointTracker()), UnauthorizedCheckpointTracker());
    }
}

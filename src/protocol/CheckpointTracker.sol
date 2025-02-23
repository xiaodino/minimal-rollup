// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IPublicationFeed} from "./IPublicationFeed.sol";
import {IVerifier} from "./IVerifier.sol";

struct Checkpoint {
    uint256 publicationId;
    bytes32 commitment;
}

contract CheckpointTracker {
    /// @notice The current proven checkpoint representing the latest verified state of the rollup
    /// @dev Previous checkpoints are not stored here but are synchronized to the `SignalService`
    /// @dev A checkpoint commitment is any value (typically a state root) that uniquely identifies
    /// the state of the rollup at a specific point in time
    Checkpoint public checkpoint;

    /// @notice Verified transitions between two checkpoints
    /// @dev the startCheckpoint is not necessarily valid, but the endCheckpoint is correctly built on top of it.
    mapping(bytes32 endCheckpointHash => bytes32 startCheckpointHash) private transitions;

    IPublicationFeed public immutable publicationFeed;

    // This would usually be retrieved dynamically as in the current Taiko implementation, but for simplicity we are
    // just setting it in the constructor
    IVerifier public immutable verifier;

    /// @notice Emitted when a checkpoint is proven
    /// @param publicationId the index of the publication at which the commitment was proven
    /// @param commitment the checkpoint commitment that was proven
    event CheckpointProven(uint256 indexed publicationId, bytes32 indexed commitment);

    /// @param genesis the checkpoint commitment describing the initial state of the rollup
    /// @param _publicationFeed the input data source that updates the state of this rollup
    /// @param _verifier a contract that can verify the validity of a transition from one checkpoint to another
    constructor(bytes32 genesis, address _publicationFeed, address _verifier) {
        // set the genesis checkpoint commitment of the rollup - genesis is trusted to be correct
        require(genesis != 0, "genesis checkpoint commitment cannot be 0");
        checkpoint.commitment = genesis;
        publicationFeed = IPublicationFeed(_publicationFeed);
        verifier = IVerifier(_verifier);
    }

    /// @notice Verifies a transition between two checkpoints. Update the latest `checkpoint` if possible
    /// @param start The initial checkpoint before the transition
    /// @param end The final checkpoint after the transition
    /// @param proof Arbitrary data passed to the `verifier` contract to confirm the transition validity
    function proveTransition(Checkpoint calldata start, Checkpoint calldata end, bytes calldata proof)
        external
    {
        bytes32 startCheckpointHash = keccak256(abi.encode(start));
        bytes32 endCheckpointHash = keccak256(abi.encode(end));

        require(end.commitment != 0, "Checkpoint commitment cannot be 0");
        // TODO: once the proving incentive mechanism is in place we should reconsider this requirement because
        // ideally we would use the proof that creates the longest chain of proven publications.
        require(transitions[endCheckpointHash] == 0, "End checkpoint already verified");
        require(start.publicationId < end.publicationId, "Start must be before end");
        require(end.publicationId < publicationFeed.getNextPublicationId(), "Publication does not exist");

        verifier.verifyProof(
            publicationFeed.getPublicationHash(start.publicationId),
            publicationFeed.getPublicationHash(end.publicationId),
            start.commitment,
            end.commitment,
            proof
        );

        transitions[endCheckpointHash] = startCheckpointHash;
    }

    /// @notice Verifies and updates the rollup state with a new checkpoint
    /// @param newCheckpoint The proposed new checkpoint value to transition to
    /// @param proof Arbitrary data passed to the `_verifier` contract to confirm the transition validity.
    function proveLatestTransition(Checkpoint calldata newCheckpoint, bytes calldata proof) external {
        require(newCheckpoint.commitment != 0, "Commitment cannot be 0");
        require(newCheckpoint.publicationId > checkpoint.publicationId, "Publication already proven");

        verifier.verifyProof(
            publicationFeed.getPublicationHash(checkpoint.publicationId),
            publicationFeed.getPublicationHash(newCheckpoint.publicationId),
            checkpoint.commitment,
            newCheckpoint.commitment,
            proof
        );

        checkpoint = newCheckpoint;

        emit CheckpointProven(newCheckpoint.publicationId, newCheckpoint.commitment);
    }
}

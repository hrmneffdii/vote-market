// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title IPosition
 * @notice Defines the external interface for the Position contract, which manages
 * outcome tokens (positions) as ERC-1155 tokens.
 */
interface IPosition {
    //===========================================
    //                 Events
    //===========================================

    event PositionControllerChanged(address oldController, address _newController); 

    //===========================================
    //                 Errors
    //===========================================

    /// @notice Reverts if the caller is not authorized (e.g., not the Controller).
    error UnauthorizedCaller();
    /// @notice Reverts if minting or burning to/from the zero address.
    error NonZeroAddress();

    //===========================================
    //           Mint/Burn Functions
    //===========================================

    /**
     * @notice Mints multiple types of outcome tokens to a user.
     * @dev Typically called by an authorized Controller (e.g., after a trade).
     * @param _to The address to mint tokens to.
     * @param _ids The array of token IDs (generated from marketId + outcome).
     * @param _amounts The array of amounts to mint for each token ID.
     */
    function mintBatch(
        address _to,
        uint256[] calldata _ids,
        uint256[] calldata _amounts
    ) external;

    /**
     * @notice Burns a specific amount of a single outcome token from an account.
     * @dev Typically called by an authorized Controller (e.g., when redeeming winnings).
     * @param _from The address to burn tokens from.
     * @param _id The token ID to burn.
     * @param _amount The amount to burn.
     */
    function burn(address _from, uint256 _id, uint256 _amount) external;

    /**
     * @notice Burns multiple types of outcome tokens from an account.
     * @dev Typically called by an authorized Controller.
     * @param _from The address to burn tokens from.
     * @param _ids The array of token IDs to burn.
     * @param _amounts The array of amounts to burn for each token ID.
     */
    function burnBatch(
        address _from,
        uint256[] calldata _ids,
        uint256[] calldata _amounts
    ) external;

    //===========================================
    //             View Functions
    //===========================================

    /**
     * @notice Calculates the unique ERC-1155 token ID for a specific market outcome.
     * @param _marketId The unique identifier for the market.
     * @param _outcome The index of the outcome (e.t., 0 for NO, 1 for YES).
     * @return The unique token ID as a uint256.
     */
    function getTokenId(
        bytes32 _marketId,
        uint256 _outcome
    ) external view returns (uint256);
}
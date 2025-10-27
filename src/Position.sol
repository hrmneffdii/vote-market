// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {IPosition} from "./interfaces/IPosition.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

/**
 * @title Position
 * @notice An ERC-1155 contract to represent prediction market outcome tokens.
 * @dev This contract creates and manages the supply of outcome tokens (positions).
 * Minting and burning are restricted to an authorized Controller contract.
 */
contract Position is IPosition, ERC1155, Ownable {
    //===========================================
    //             State Variables
    //===========================================

    /// @notice The authorized Controller contract permitted to mint and burn tokens.
    address public controller;

    //===========================================
    //               Modifiers
    //===========================================

    modifier onlyController() {
        if (msg.sender != controller) revert UnauthorizedCaller();
        _;
    }

    //===========================================
    //              Constructor
    //===========================================

    /**
     * @notice Initializes the Position contract.
     * @param _initialOwner The address of the contract owner (admin).
     * @param _initialController The address of the authorized Controller contract.
     */
    constructor(address _initialOwner, address _initialController) Ownable(_initialOwner) ERC1155("") {
        // No base URI needed
        if (_initialOwner == address(0)) revert NonZeroAddress();
        if (_initialController == address(0)) revert NonZeroAddress();

        controller = _initialController;
    }

    //===========================================
    //          Mint/Burn Functions
    //===========================================

    function mint(address _to, uint256 _id, uint256 _amount) external onlyController {
        _mint(_to, _id, _amount, "");
    }

    /**
     * @notice Mints multiple types of outcome tokens to a user.
     * @dev Called only by the Controller. Wraps the internal ERC1155 _mintBatch.
     * @param _to The address to mint tokens to.
     * @param _ids The array of token IDs to mint.
     * @param _amounts The array of amounts to mint for each token ID.
     */
    function mintBatch(address _to, uint256[] memory _ids, uint256[] memory _amounts)
        external
        override
        onlyController
    {
        _mintBatch(_to, _ids, _amounts, "");
    }

    /**
     * @notice Burns a specific amount of a single outcome token from an account.
     * @dev Called only by the Controller. Wraps the internal ERC1155 _burn.
     * @param _from The address to burn tokens from.
     * @param _id The token ID to burn.
     * @param _amount The amount to burn.
     */
    function burn(address _from, uint256 _id, uint256 _amount) external override onlyController {
        _burn(_from, _id, _amount);
    }

    /**
     * @notice Burns multiple types of outcome tokens from an account.
     * @dev Called only by the Controller. Wraps the internal ERC1155 _burnBatch.
     * @param _from The address to burn tokens from.
     * @param _ids The array of token IDs to burn.
     * @param _amounts The array of amounts to burn for each token ID.
     */
    function burnBatch(address _from, uint256[] memory _ids, uint256[] memory _amounts)
        external
        override
        onlyController
    {
        _burnBatch(_from, _ids, _amounts);
    }

    //===========================================
    //              Owner Functions
    //===========================================

    /**
     * @notice Updates the address of the authorized Controller contract.
     * @param _newController The address of the new Controller.
     */
    function setController(address _newController) external onlyOwner {
        if (_newController == address(0)) revert NonZeroAddress();

        address oldController = controller;
        controller = _newController;

        emit PositionControllerChanged(oldController, _newController); // Assumes event in IPosition
    }

    //===========================================
    //               View Functions
    //===========================================

    /**
     * @notice Calculates the unique ERC-1155 token ID for a specific market outcome.
     * @dev This provides a deterministic way to link a market/outcome pair to a token ID.
     * @param _marketId The unique identifier for the market.
     * @param _outcome The index of the outcome.
     * @return The unique token ID as a uint256.
     */
    function getTokenId(bytes32 _marketId, uint256 _outcome) external pure override returns (uint256) {
        // Cast the keccak256 hash (bytes32) to uint256 for the token ID
        return uint256(keccak256(abi.encode(_marketId, _outcome)));
    }
}

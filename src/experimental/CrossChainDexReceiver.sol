// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {SafeTransferLib} from "lib/solady/src/utils/SafeTransferLib.sol";

import {IStargate} from "./interfaces/IStargate.sol";
import {MessagingFee, OFTReceipt, SendParam} from "./interfaces/IOFT.sol";
import {ILayerZeroComposer} from "./interfaces/ILayerZeroComposer.sol";
import {OFTComposeMsgCodec} from "../libs/OFTComposeMsgCodec.sol";
import {IUniswapV2Router02} from "./interfaces/IUniswapV2Router02.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract CrossChainDexReceiver is Ownable, ReentrancyGuard, Pausable, ILayerZeroComposer {
    using SafeTransferLib for address;

    error InvalidFromAddress(address);
    error UnauthorisedAccess(address);
    error TransferFailed(address token, address owner);

    IStargate private stargatePoolUSDC;
    IUniswapV2Router02 private routerV2;
    address public endpoint;

    event BridgeAsset(address indexed user, address indexed token, uint256 amount, uint32 dstId);
    event WithdrawToken(address indexed owner, address indexed token, uint256 amount);
    event SafeTransfer(
        bytes32 indexed guid,
        address indexed sender,
        address indexed tokenReceiver,
        address oftOnDestination,
        uint256 amountLD
    );
    event SwapTokens(
        bytes32 indexed guid,
        address indexed sender,
        address indexed tokenReceiver,
        address tokenIn,
        uint256 amounIn,
        address tokenOut,
        uint256 amountOut
    );
    event ComposeAcknowledged(
        address indexed _from, bytes32 indexed _guid, bytes _message, address _executor, bytes _extraData
    );

    constructor(address _owner, address _stargatePoolUSDC, address _endpoint, address _routerV2) Ownable() {
        stargatePoolUSDC = IStargate(_stargatePoolUSDC);
        endpoint = _endpoint;
        routerV2 = IUniswapV2Router02(_routerV2);
        _transferOwnership(_owner);
    }

    /**
     * @notice Composes a LayerZero message from an OApp.
     * @param _from The address initiating the composition, typically the OApp where the lzReceive was called.
     * @param _guid The unique identifier for the corresponding LayerZero src/dst tx.
     * @param _message The composed message payload in bytes. NOT necessarily the same payload passed via lzReceive.
     * @param _executor The address of the executor for the composed message.
     * @param _extraData Additional arbitrary data in bytes passed by the entity who executes the lzCompose.
     */
    function lzCompose(
        address _from,
        bytes32 _guid,
        bytes calldata _message,
        address _executor,
        bytes calldata _extraData
    ) external payable whenNotPaused nonReentrant {
        // if (_from != address(stargatePoolUSDC)) {
        //     revert InvalidFromAddress(_from);
        // }
        // if (msg.sender != endpoint) {
        //     revert UnauthorisedAccess(msg.sender);
        // }

        uint256 amountLD = OFTComposeMsgCodec.amountLD(_message);
        bytes memory _composeMessage = OFTComposeMsgCodec.composeMsg(_message);

        (
            address _tokenReceiver,
            address _oftOnDestination,
            address _tokenOut,
            uint256 _amountOutMinDest,
            uint256 _deadline
        ) = abi.decode(_composeMessage, (address, address, address, uint256, uint256));

        address[] memory path = new address[](2);
        path[0] = _oftOnDestination;
        path[1] = _tokenOut;

        _oftOnDestination.safeApprove(address(routerV2), amountLD);

        // Replace this with an aggregator swap function (1inch router  )
        try routerV2.swapExactTokensForTokens(amountLD, _amountOutMinDest, path, _tokenReceiver, _deadline) returns (
            uint256[] memory amounts
        ) {
            emit SwapTokens(
                _guid, _from, _tokenReceiver, _oftOnDestination, amounts[0], _tokenOut, amounts[amounts.length - 1]
            );
        } catch {
            _oftOnDestination.safeTransfer(_tokenReceiver, amountLD);
            emit SafeTransfer(_guid, _from, _tokenReceiver, _oftOnDestination, amountLD);
        }
        emit ComposeAcknowledged(_from, _guid, _message, _executor, _extraData);
    }

    function withdrawDust() external nonReentrant onlyOwner {
        uint256 balance = address(this).balance;
        (bool success,) = owner().call{value: balance}("");
        if (!success) {
            revert TransferFailed(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE, owner());
        }
    }

    function withdrawDustTokens(address[] calldata tokens) external nonReentrant onlyOwner {
        uint256 length = tokens.length;
        for (uint256 i = 0; i < length; i++) {
            uint256 balance = IERC20(tokens[i]).balanceOf(address(this));
            address(tokens[i]).safeTransfer(owner(), balance);
            emit WithdrawToken(owner(), tokens[i], balance);
        }
    }

    /**
     * @dev Address to bytes32 converter
     */
    function addressToBytes32(address _addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }

    /**
     * @dev Pauses the contract
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpauses the contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev Receive function to accept native currency
     */
    receive() external payable {}

    /**
     * @dev Fallback function
     */
    fallback() external payable {}
}

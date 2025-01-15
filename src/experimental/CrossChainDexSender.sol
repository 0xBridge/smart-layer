// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {SafeTransferLib} from "lib/solady/src/utils/SafeTransferLib.sol";

import {IStargate} from "./interfaces/IStargate.sol";
import {MessagingFee, OFTReceipt, SendParam} from "./interfaces/IOFT.sol";
import {OptionsBuilder} from "../libs/OptionsBuilder.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract CrossChainDexSender is Ownable, ReentrancyGuard, Pausable {
    using SafeTransferLib for address;

    error TransferFailed(address token, address owner);

    IStargate private stargatePoolUSDC;

    event BridgeAsset(
        address indexed tokenReceiver,
        address indexed oftOnDestinationAddress,
        address indexed tokenOut,
        uint256 amount,
        uint32 dstId
    );

    event WithdrawToken(address indexed owner, address indexed token, uint256 amount);

    constructor(address _owner, address _stargatePoolUSDC) {
        stargatePoolUSDC = IStargate(_stargatePoolUSDC);
        _transferOwnership(_owner);
    }

    function crossChainSwap(
        address _tokenReceiver,
        address _composer,
        uint32 _dstEid,
        uint256 _amount,
        address _refundAddress,
        address _oftOnDestinationAddress,
        address _tokenOut,
        uint256 _amountOutMinDest,
        uint256 _deadline
    ) external payable whenNotPaused nonReentrant {
        address token = stargatePoolUSDC.token();
        // Pull assets from the user
        token.safeTransferFrom(msg.sender, address(this), _amount);

        // Approve stargatePoolUSDC to take assets from this contract
        token.safeApprove(address(stargatePoolUSDC), _amount);

        // Setup params required to send tokens via stargatePoolUSDC
        if (_refundAddress == address(0)) {
            _refundAddress = msg.sender;
        }

        bytes memory _composeMsg =
            prepareComposeMessage(_tokenReceiver, _oftOnDestinationAddress, _tokenOut, _amountOutMinDest, _deadline);
        (uint256 valueToSend, SendParam memory sendParam, MessagingFee memory messagingFee) =
            prepareTakeTaxi(_dstEid, _amount, _composer, _composeMsg);
        stargatePoolUSDC.sendToken{value: valueToSend}(sendParam, messagingFee, _refundAddress);
        emit BridgeAsset(_tokenReceiver, _oftOnDestinationAddress, _tokenOut, _amount, _dstEid);
    }

    /**
     * @dev Generate params to send via stargatePoolUSDC
     */
    function prepareTakeTaxi(uint32 _dstEid, uint256 _amount, address _composer, bytes memory _composeMsg)
        public
        view
        returns (uint256 valueToSend, SendParam memory sendParam, MessagingFee memory messagingFee)
    {
        bytes memory extraOptions = _composeMsg.length > 0
            ? OptionsBuilder.addExecutorLzComposeOption(OptionsBuilder.newOptions(), 0, 200_000, 0)
            : bytes("");

        sendParam = SendParam({
            dstEid: _dstEid,
            to: addressToBytes32(_composer),
            amountLD: _amount,
            minAmountLD: _amount,
            extraOptions: extraOptions,
            composeMsg: _composeMsg,
            oftCmd: ""
        });

        (,, OFTReceipt memory receipt) = stargatePoolUSDC.quoteOFT(sendParam);

        sendParam.minAmountLD = receipt.amountReceivedLD;

        messagingFee = stargatePoolUSDC.quoteSend(sendParam, false);
        valueToSend = messagingFee.nativeFee;

        if (stargatePoolUSDC.token() == address(0x0)) {
            valueToSend += sendParam.amountLD;
        }
    }

    function prepareComposeMessage(
        address _tokenReceiver,
        address _oftOnDestinationAddress,
        address _tokenOut,
        uint256 _amountOutMinDest,
        uint256 _deadline
    ) public pure returns (bytes memory composeMsg) {
        composeMsg = abi.encode(_tokenReceiver, _oftOnDestinationAddress, _tokenOut, _amountOutMinDest, _deadline);
    }

    function withdrawDust() external nonReentrant onlyOwner {
        uint256 balance = address(this).balance;
        (bool success,) = owner().call{value: balance}("");
        if (!success) {
            revert TransferFailed(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE, owner()); // For native token
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

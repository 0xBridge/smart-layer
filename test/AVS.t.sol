// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, Vm} from "forge-std/Test.sol";

interface IAttestationCenter {
    struct TaskInfo {
        string proofOfTask;
        bytes data;
        address taskPerformer;
        uint16 taskDefinitionId;
    }

    function submitTask(
        TaskInfo calldata _taskInfo,
        bool _isApproved,
        bytes calldata _tpSignature,
        uint256[2] calldata _taSignature,
        uint256[] calldata _attestersIds
    ) external;
}

// Deployed on Holesky at 0xa44151489861fe9e3055d95adc98fbd462b948e7
interface IELDelegationManagerAddress {
    // ZERO_ADDRESS, 0, https://othentic.mypinata.cloud/ipfs/QmTYcrU2qiA2mrCvch3opXm5VigcX6Uyok6jdnKm6ghNAL/operator.json (metadata of operator)
    function registerAsOperator(address initDelegationApprover, uint32 allocationDelay, string calldata metadataURI)
        external;
}

// Deployed on Holesky at 0x3F1c547b21f65e10480dE3ad8E19fAAC46C95034
interface IstETH {
    function approve(address spender, uint256 value) external;
    function submit(address _referral) external payable;
}

// Deployed on Holesky at 0xdfB5f6CE42aAA7830E94ECFCcAd411beF4d4D5b6
interface IStrategyManager {
    function depositIntoStrategy(address strategy, address token, uint256 amount) external;
}

// interface
contract AVSTest is Test {
    // Amoy Variables

    // Holesky Variables
    // This would change for every operator
    string private metadataURI =
        "https://othentic.mypinata.cloud/ipfs/QmTYcrU2qiA2mrCvch3opXm5VigcX6Uyok6jdnKm6ghNAL/operator.json";
    uint256 private ethAmountToStake = 1 ether;

    // 1. Deploy the AVS contracts - Done via the Othentic cli
    // Amoy deployed addresses
    address private constant ATTESTATION_CENTER = 0x276ef26eEDC3CFE0Cdf22fB033Abc9bF6b6a95B3;
    address private constant L2_MESSAGE_HANDLER = 0x99cFa1A168545F9f19218b0D6a0654b95d57842a;
    address private constant OBLS = 0xc5b801467f74C9306ddD30a0CeFfeDEA89A5c91a;
    address private constant INTERNAL_TASK_HANDLER = 0x878eD42Aae7a3aF424DF42F78469C21b71124C5d;

    // Amoy constants
    address private constant ZERO_ADDRESS = address(0);

    // Holesky deployed addresses
    address private constant AVS_GOVERNANCE_ADDRESS = 0xD23c43e9742be53029A0964C10c28EE3203420D1;
    address private constant AVS_TREASURY = 0xa446A9fEd7527BbdbF16305fA2b04Ab4a2F4E386;
    address private constant WETH = 0x94373a4919B3240D86eA41593D5eBa789FEF3848;
    address private constant L1_MESSAGE_HANDLER = 0xf8fc6e50865A0dB5493A435f9C31C24161E114FC;

    // Holesky constants
    address private constant EL_DELEGATION_MANAGER = 0xA44151489861Fe9e3055d95adC98FbD462B948e7;
    address private constant STAKED_ETH = 0x3F1c547b21f65e10480dE3ad8E19fAAC46C95034;
    address private constant LIDO_REFERRAL_ADDRESS = 0x11d00000000000000000000000000000000011d0;
    address private constant EL_STRATEGY_MANAGER = 0xdfB5f6CE42aAA7830E94ECFCcAd411beF4d4D5b6;
    address private constant ST_ETH_STRATEGY = 0x7D704507b76571a51d9caE8AdDAbBFd0ba0e63d3;

    function setUp() public {
        // 1. Deploy the AVS contracts - this can be done via the Othentic cli

        // 2. Register the necessary performer/operators/attesters/aggregators on EigenLayer - to be executed by the deployer / AVS Multisig owner
        // https://holesky.etherscan.io/tx/0x5e99ffa3be63df189d5e61309480e902ace42b65fbed715ee8432cc1a0e754df
        address initDelegationApprover = ZERO_ADDRESS;
        uint32 allocationDelay = 0;
        IELDelegationManagerAddress(EL_DELEGATION_MANAGER).registerAsOperator(
            initDelegationApprover, allocationDelay, metadataURI
        );

        // 3. Get stETH token (convert ETH to stETH) - to be executed by the operators individually
        // https://holesky.etherscan.io/tx/0xb76183b2f5d06f6d2d6f253fedb4d331e190f69886e9e65e2b4cb9bff327ddd4
        IstETH(STAKED_ETH).submit{value: ethAmountToStake}(LIDO_REFERRAL_ADDRESS);

        // 4. Deposit into strategy to setup operator voting power (for all three operators)
        // https://holesky.etherscan.io/tx/0x905df28a75ddc9d84b1f50304345ddadc6cc47576989ae5d60cfcb310a4720d6
        IstETH(STAKED_ETH).approve(EL_STRATEGY_MANAGER, ethAmountToStake);
        IStrategyManager(EL_STRATEGY_MANAGER).depositIntoStrategy(ST_ETH_STRATEGY, STAKED_ETH, ethAmountToStake);

        // 5. Register operators to AVS (same as step 1) - This one is a fourth one
        // https://holesky.etherscan.io/tx/0xbec6a362cf15c06cfc3932684518fe9367e851cdbac873531d5d6c16e45b2ce6
        // https://holesky.etherscan.io/tx/0x8b61105ecfc3cd2207b58fade0784039d67c21f353f9bda681ba7c63713daaee

        // Unpause first to allow rewards disburse - defaulted to pause

        // 6. Make sure the rewards are deposited to the AVS treasury
        // https://holesky.etherscan.io/tx/0x11b41b58d6780dd477fe7cbf51d8c252745cd4606edc6377f366ea9e8e256a51

        // 7. Claim Rewards on L1 - how is this possible but
    }

    // Create the required task -

    // Submit it to the AttestationCenter via the submitTask function

    // Currently, all the above happens in one go via the Othentic cli
    function testSubmitTask() public {
        // Create the AttestationCenter contract
        IAttestationCenter attestationCenter = IAttestationCenter(0x1234567890123456789012345678901234567890);

        // Create the task info
        IAttestationCenter.TaskInfo memory taskInfo = IAttestationCenter.TaskInfo({
            proofOfTask: "Proof of task",
            data: "Data",
            taskPerformer: address(0x1234567890123456789012345678901234567890),
            taskDefinitionId: 1
        });

        // Submit the task
        // attestationCenter.submitTask(taskInfo, true, "TP Signature", [1, 2], [1, 2, 3]);
    }
}

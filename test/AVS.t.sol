// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, Vm} from "forge-std/Test.sol";
import {ISignatureUtils} from
    "@eigenlayer-middleware/lib/eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

library BLSAuthLibrary {
    struct Signature {
        uint256[2] signature;
    }
}

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

    function unpause(bytes4 _pausableFlow) external;
    function requestBatchPayment() external;
}

// Deployed on Holesky at 0xa44151489861fe9e3055d95adc98fbd462b948e7
interface IELDelegationManagerAddress {
    // ZERO_ADDRESS, 0, https://othentic.mypinata.cloud/ipfs/QmTYcrU2qiA2mrCvch3opXm5VigcX6Uyok6jdnKm6ghNAL/operator.json (metadata of operator)
    function registerAsOperator(address initDelegationApprover, uint32 allocationDelay, string calldata metadataURI)
        external;
}

// Deployed on Holesky at 0x3F1c547b21f65e10480dE3ad8E19fAAC46C95034
interface ILiquidStakedEther {
    function approve(address spender, uint256 value) external;
    function submit(address _referral) external payable;
}

// Deployed on Holesky at 0xdfB5f6CE42aAA7830E94ECFCcAd411beF4d4D5b6
interface IStrategyManager {
    function depositIntoStrategy(address strategy, address token, uint256 amount) external;
}

interface IAVSGovernance {
    // function registerOperatorToEigenLayer(_eigenSig) external;
    function registerAsOperator(
        uint256[4] calldata _blsKey,
        address _rewardsReceiver,
        ISignatureUtils.SignatureWithSaltAndExpiry memory _operatorSignature,
        BLSAuthLibrary.Signature calldata _blsRegistrationSignature
    ) external;
}

interface IVault {
    function depositERC20(address token, uint256 amountWithFee) external;
}

// interface
contract AVSTest is Test {
    address private constant SIGNER = 0x71cf07d9c0D8E4bBB5019CcC60437c53FC51e6dE;

    // Amoy Variables
    uint256 private homeForkId;

    // Holesky Variables
    // This would change for every operator
    string private metadataURI =
        "https://othentic.mypinata.cloud/ipfs/QmTYcrU2qiA2mrCvch3opXm5VigcX6Uyok6jdnKm6ghNAL/operator.json";
    uint256 private ethAmountToStake = 1 ether;
    uint256 private wethTreasuryAmountDeposit = 10 ether;

    // Amoy deployed addresses
    address private constant ATTESTATION_CENTER = 0x276ef26eEDC3CFE0Cdf22fB033Abc9bF6b6a95B3;
    address private constant L2_MESSAGE_HANDLER = 0x99cFa1A168545F9f19218b0D6a0654b95d57842a;
    address private constant OBLS = 0xc5b801467f74C9306ddD30a0CeFfeDEA89A5c91a;
    address private constant INTERNAL_TASK_HANDLER = 0x878eD42Aae7a3aF424DF42F78469C21b71124C5d;

    // Amoy constants
    address private constant ZERO_ADDRESS = address(0);
    bytes4 private constant REWARDS_FLOW = 0xc6d72715; // 0xc6d72715 - RewardsFlow
    address private constant AVS_MULTISIG_OWNER = 0x4E56a8E3757F167378b38269E1CA0e1a1F124C9E;

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

    // 1. Deploy the AVS contracts - Done via the Othentic cli (TODO: Test with a fresh deployment)
    function alreadyDone_setUp() public {
        // 1. Deploy the AVS contracts - this can be done via the Othentic cli

        // 2. Register the necessary performer/operators/attesters/aggregators on EigenLayer - to be executed by the deployer / AVS Multisig owner
        // https://holesky.etherscan.io/tx/0x5e99ffa3be63df189d5e61309480e902ace42b65fbed715ee8432cc1a0e754df
        address initDelegationApprover = ZERO_ADDRESS;
        uint32 allocationDelay = 0;
        IELDelegationManagerAddress(EL_DELEGATION_MANAGER).registerAsOperator(
            initDelegationApprover, allocationDelay, metadataURI
        ); // Deployer (AVS_MULTISIG_OWNER)

        // 3. Get stETH token (convert ETH to stETH) - to be executed by the operators individually
        // https://holesky.etherscan.io/tx/0xb76183b2f5d06f6d2d6f253fedb4d331e190f69886e9e65e2b4cb9bff327ddd4
        ILiquidStakedEther(STAKED_ETH).submit{value: ethAmountToStake}(LIDO_REFERRAL_ADDRESS);

        // 4. Deposit into strategy to setup operator voting power - to be executed by the operators individually
        // https://holesky.etherscan.io/tx/0x905df28a75ddc9d84b1f50304345ddadc6cc47576989ae5d60cfcb310a4720d6
        ILiquidStakedEther(STAKED_ETH).approve(EL_STRATEGY_MANAGER, ethAmountToStake);
        IStrategyManager(EL_STRATEGY_MANAGER).depositIntoStrategy(ST_ETH_STRATEGY, STAKED_ETH, ethAmountToStake);

        // 5. Register operators to AVS (same as step 1) - to be executed by the operators individually
        // https://holesky.etherscan.io/tx/0xbec6a362cf15c06cfc3932684518fe9367e851cdbac873531d5d6c16e45b2ce6
        // https://holesky.etherscan.io/tx/0x8b61105ecfc3cd2207b58fade0784039d67c21f353f9bda681ba7c63713daaee
        // IAVSGovernance(AVS_GOVERNANCE_ADDRESS).registerOperatorToEigenLayer(_eigenSig);
        // IAVSGovernance(AVS_GOVERNANCE_ADDRESS).registerAsOperator(uint256[4] calldata _blsKey, address _rewardsReceiver, ISignatureUtils.SignatureWithSaltAndExpiry memory _operatorSignature, BLSAuthLibrary.Signature calldata _blsRegistrationSignature);

        // 6. Make sure the rewards are deposited to the AVS treasury
        // https://holesky.etherscan.io/tx/0x11b41b58d6780dd477fe7cbf51d8c252745cd4606edc6377f366ea9e8e256a51
        IERC20(WETH).approve(AVS_TREASURY, wethTreasuryAmountDeposit);
        IVault(AVS_TREASURY).depositERC20(WETH, wethTreasuryAmountDeposit); // Deployer (AVS_MULTISIG_OWNER)

        // Unpause first to allow rewards disburse - defaulted to pause
        // https://amoy.polygonscan.com/tx/0x5fd0a7919ae8af9785cccf670dfb0ad9897bdfc7a6b2f50156cb1453063f55c4
        IAttestationCenter(ATTESTATION_CENTER).unpause(REWARDS_FLOW); // Deployer (AVS_MULTISIG_OWNER)

        // 7. Claim Rewards - Can be done post submitTask (Didn't see the rewards disbursed on L1)
        // https://amoy.polygonscan.com/tx/0xa733561e71a50530177c8c92e08c95cefb0263f92572a99f8f9c80d63895b5af
        // IAttestationCenter(ATTESTATION_CENTER).requestBatchPayment(); // Deployer (AVS_MULTISIG_OWNER)
    }

    function setUp() public {
        // Create and select the network on which the task is to be submitted
        string memory homeRpcUrl = vm.envString("AMOY_RPC_URL");
        homeForkId = vm.createSelectFork(homeRpcUrl);
    }

    // Submit it to the AttestationCenter via the submitTask function
    // Currently, all the above happens in one go via the Othentic cli
    function testSubmitTask() public {
        // Create the AttestationCenter contract
        IAttestationCenter attestationCenter = IAttestationCenter(ATTESTATION_CENTER);

        // Create the task info
        IAttestationCenter.TaskInfo memory taskInfo = IAttestationCenter.TaskInfo({
            proofOfTask: "QmVgZ7wnP8fMfpAtqGPbJAmUT8AMumtyahwUEhoodcyMUG",
            data: hex"4920616d2049726f6e6d616e21", // hex bytes data
            taskPerformer: SIGNER,
            taskDefinitionId: 0
        });

        // Submit the task (TODO: Figure this part out)
        bytes memory tpSignature =
            hex"58ae6a69ddab6e1e661db8fbcbc8ede05f9e43941325fb462aaa54fd565b5c89704d5a0a45f1229ee6c648d0e647d3b93087bbd520e5fd32bd37dee19662a4421b";
        uint256[2] memory taSignature = [
            9093911615789399830602974754443205710846914036477274464096283111600022727438,
            11541948654984445339530075522406573357857067838037210814544443461153759883923
        ];
        uint256[] memory attestersIds = new uint256[](2);
        attestersIds[0] = 3;
        attestersIds[1] = 4;

        vm.prank(SIGNER);
        attestationCenter.submitTask(taskInfo, true, tpSignature, taSignature, attestersIds);

        // Distribute rewards
        // attestationCenter.requestBatchPayment(); // Deployer (AVS_MULTISIG_OWNER)
    }
}

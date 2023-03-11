// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {AddressManager} from "../contracts/thirdparty/AddressManager.sol";
import {TaikoConfig} from "../contracts/L1/TaikoConfig.sol";
import {TaikoData} from "../contracts/L1/TaikoData.sol";
import {TaikoL1} from "../contracts/L1/TaikoL1.sol";
import {TaikoToken} from "../contracts/L1/TaikoToken.sol";
import {SignalService} from "../contracts/signal/SignalService.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract TaikoL1WithConfig is TaikoL1 {
    function getConfig()
        public
        pure
        override
        returns (TaikoData.Config memory config)
    {
        config = TaikoConfig.getConfig();
        config.maxNumBlocks = 5;
        config.maxVerificationsPerTx = 0;
        config.enableSoloProposer = false;
        config.enableOracleProver = false;
    }
}

contract Verifier {
    fallback(bytes calldata) external returns (bytes memory) {
        return bytes.concat(keccak256("taiko"));
    }
}

contract TaikoL1Test is Test {
    TaikoToken public tko;
    TaikoL1WithConfig public L1;
    TaikoData.Config conf;
    SignalService public ss;
    uint256 logCount;

    bytes32 public constant GENESIS_BLOCK_HASH =
        keccak256("GENESIS_BLOCK_HASH");
    address public constant L2SS = 0xDAFEA492D9c6733ae3d56b7Ed1ADB60692c98Bc5;
    address public constant ALICE = 0xc8885E210E59Dba0164Ba7CDa25f607e6d586B7A;
    address public constant BOB = 0x000000000000000000636F6e736F6c652e6c6f67;

    AddressManager public addressManager;

    function setUp() public {
        addressManager = new AddressManager();
        addressManager.init();

        uint64 feeBase = 1E18;
        L1 = new TaikoL1WithConfig();
        L1.init(address(addressManager), GENESIS_BLOCK_HASH, feeBase);
        conf = L1.getConfig();
        _printVariables();

        tko = new TaikoToken();
        tko.init(address(addressManager), "TaikoToken", "TKO");

        ss = new SignalService();
        ss.init(address(addressManager));

        // set proto_broker to this address to mint some TKO
        _registerAddress("proto_broker", address(this));
        tko.mint(address(this), 1E12 ether);

        // register all addresses
        _registerAddress("taiko_token", address(tko));
        _registerAddress("proto_broker", address(L1));
        _registerAddress("signal_service", address(ss));
        _registerL2Address("signal_service", address(L2SS));
        _registerAddress(
            string(abi.encodePacked("verifier_", uint256(100))),
            address(new Verifier())
        );
    }

    function proposeBlock(
        address proposer,
        uint256 txListSize
    ) internal returns (TaikoData.BlockMetadata memory meta) {
        uint64 gasLimit = 1000000;
        bytes memory txList = new bytes(txListSize);
        TaikoData.BlockMetadataInput memory input = TaikoData
            .BlockMetadataInput({
                beneficiary: proposer,
                gasLimit: gasLimit,
                txListHash: keccak256(txList)
            });

        TaikoData.StateVariables memory variables = L1.getStateVariables();

        uint256 _mixHash;
        unchecked {
            _mixHash = block.prevrandao * variables.nextBlockId;
        }

        meta.id = variables.nextBlockId;
        meta.l1Height = block.number - 1;
        meta.l1Hash = blockhash(block.number - 1);
        meta.beneficiary = proposer;
        meta.txListHash = keccak256(txList);
        meta.mixHash = bytes32(_mixHash);
        meta.gasLimit = gasLimit;
        meta.timestamp = uint64(block.timestamp);

        vm.prank(proposer, proposer);
        L1.proposeBlock(abi.encode(input), txList);
        _printVariables();
        _mine(1);
    }

    function proveBlock(
        address prover,
        TaikoData.BlockMetadata memory meta,
        bytes32 parentHash,
        bytes32 blockHash,
        bytes32 signalRoot
    ) internal {
        TaikoData.ZKProof memory zkproof = TaikoData.ZKProof({
            data: new bytes(100),
            circuitId: 100
        });

        TaikoData.BlockEvidence memory evidence = TaikoData.BlockEvidence({
            meta: meta,
            zkproof: zkproof,
            parentHash: parentHash,
            blockHash: blockHash,
            signalRoot: signalRoot,
            prover: prover
        });

        vm.prank(prover, prover);
        L1.proveBlock(meta.id, abi.encode(evidence));
        _printVariables();
        _mine(1);
    }

    function testProposeSingleBlock() external {
        _depositTaikoToken(ALICE, 1E6, 100);
        _depositTaikoToken(BOB, 1E6, 100);

        bytes32 parentHash = GENESIS_BLOCK_HASH;

        for (uint blockId = 1; blockId < conf.maxNumBlocks * 10; blockId++) {
            TaikoData.BlockMetadata memory meta = proposeBlock(ALICE, 1024);
            bytes32 blockHash = bytes32(1E10 + blockId);
            bytes32 signalRoot = bytes32(1E9 + blockId);

            proveBlock(BOB, meta, parentHash, blockHash, signalRoot);

            parentHash = blockHash;

            vm.prank(BOB, BOB);
            L1.verifyBlocks(1);
            _printVariables();
            _mine(1);
        }
    }

    function _registerAddress(string memory name, address addr) internal {
        string memory key = L1.keyForName(block.chainid, name);
        addressManager.setAddress(key, addr);
    }

    function _registerL2Address(string memory name, address addr) internal {
        string memory key = L1.keyForName(conf.chainId, name);
        addressManager.setAddress(key, addr);
    }

    function _depositTaikoToken(
        address who,
        uint256 amountTko,
        uint amountEth
    ) private {
        vm.deal(who, amountEth * 1 ether);
        tko.transfer(who, amountTko * 1 ether);
        vm.prank(who, who);
        L1.deposit(amountTko);
    }

    // struct StateVariables {
    //        uint256 feeBase;
    //        uint64 genesisHeight;
    //        uint64 genesisTimestamp;
    //        uint64 nextBlockId;
    //        uint64 lastProposedAt;
    //        uint64 avgBlockTime;
    //        uint64 lastBlockId;
    //        uint64 avgProofTime;
    //    }

    function _printVariables() private {
        TaikoData.StateVariables memory vars = L1.getStateVariables();
        string memory str = string.concat(
            Strings.toString(logCount++),
            "| feeBase:",
            Strings.toString(vars.feeBase / 1E12),
            " nextBlockId:",
            Strings.toString(vars.nextBlockId),
            " lastProposedAt:",
            Strings.toString(vars.lastProposedAt),
            " lastBlockId:",
            Strings.toString(vars.lastBlockId),
            " avgBlockTime:",
            Strings.toString(vars.avgBlockTime),
            " avgProofTime:",
            Strings.toString(vars.avgProofTime)
        );
        // console2.log("feeBase:",vars.feeBase/1E12);
        console2.log(str);
    }

    function _mine(uint256 counts) private {
        vm.warp(block.timestamp + 12*counts);
            vm.roll(block.number + counts);
    }
}
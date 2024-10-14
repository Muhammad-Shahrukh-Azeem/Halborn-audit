// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {Merkle} from "./murky/Merkle.sol";

import {HalbornNFT} from "../src/HalbornNFT.sol";
import {HalbornToken} from "../src/HalbornToken.sol";
import {HalbornLoans} from "../src/HalbornLoans.sol";

contract HalbornTest is Test {
    address public immutable ALICE = makeAddr("ALICE");
    address public immutable BOB = makeAddr("BOB");

    bytes32[] public ALICE_PROOF_1;
    bytes32[] public ALICE_PROOF_2;
    bytes32[] public BOB_PROOF_1;
    bytes32[] public BOB_PROOF_2;

    HalbornNFT public nft;
    HalbornToken public token;

    HalbornLoans public loans;

    function setUp() public {
        // Initialize
        Merkle m = new Merkle();
        // Test Data
        bytes32[] memory data = new bytes32[](4);
        data[0] = keccak256(abi.encodePacked(ALICE, uint256(15)));
        data[1] = keccak256(abi.encodePacked(ALICE, uint256(19)));
        data[2] = keccak256(abi.encodePacked(BOB, uint256(21)));
        data[3] = keccak256(abi.encodePacked(BOB, uint256(24)));

        // Get Merkle Root
        bytes32 root = m.getRoot(data);

        // Get Proofs
        ALICE_PROOF_1 = m.getProof(data, 0);
        ALICE_PROOF_2 = m.getProof(data, 1);
        BOB_PROOF_1 = m.getProof(data, 2);
        BOB_PROOF_2 = m.getProof(data, 3);

        assertTrue(m.verifyProof(root, ALICE_PROOF_1, data[0]));
        assertTrue(m.verifyProof(root, ALICE_PROOF_2, data[1]));
        assertTrue(m.verifyProof(root, BOB_PROOF_1, data[2]));
        assertTrue(m.verifyProof(root, BOB_PROOF_2, data[3]));

        nft = new HalbornNFT();
        nft.initialize(root, 1 ether);

        token = new HalbornToken();
        token.initialize();

        loans = new HalbornLoans(2 ether);
        loans.initialize(address(token), address(nft));

        token.setLoans(address(loans));
    }

    function testAnyoneCanOwnerCanChangeMerkleRoot() public {
        vm.startPrank(ALICE);

        bytes32 newRoot = keccak256(abi.encodePacked("newRoot"));
        nft.setMerkleRoot(newRoot);
        assertEq(nft.merkleRoot(), newRoot);
        vm.stopPrank();

        vm.startPrank(BOB);
        bytes32 anotherRoot = keccak256(abi.encodePacked("anotherRoot"));
        nft.setMerkleRoot(anotherRoot);
        vm.stopPrank();
    }

    function testLoanWithInsufficientCollateral() public {
        vm.startPrank(ALICE);

        nft.mintAirdrops(15, ALICE_PROOF_1);
        nft.approve(address(loans), 15);
        loans.depositNFTCollateral(15);

        loans.getLoan(10 ether);

        assertEq(token.balanceOf(ALICE), 10 ether, "ALICE should have received 10 ether");

        vm.stopPrank();
    }

    function testUnauthorizedUpgradeForNFT() public {
        vm.startPrank(BOB);

        bytes memory upgradeData = abi.encodeWithSignature("upgradeTo(address)", BOB);
        (bool success,) = address(nft).call(upgradeData);

        assertTrue(!success, "BOB should not be able to upgrade the contract");

        vm.stopPrank();
    }

    function testUnauthorizedUpgradeForToken() public {
        vm.startPrank(BOB);

        bytes memory upgradeData = abi.encodeWithSignature("upgradeTo(address)", BOB);
        (bool success,) = address(token).call(upgradeData);

        assertTrue(!success, "BOB should not be able to upgrade the contract");

        vm.stopPrank();
    }

    function testArbitraryMintingByChangingLoansAddress() public {
        address attackerLoans = address(0x1234);
        token.setLoans(attackerLoans);

        vm.startPrank(attackerLoans);
        token.mintToken(BOB, 100 ether);

        assertEq(token.balanceOf(BOB), 100 ether, "BOB should have received 100 ether");

        vm.stopPrank();
    }
}

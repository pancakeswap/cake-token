// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";

/// @dev Minimal interface for the on-chain CAKE token. Mirrors the public ABI
///      of src/CakeToken.sol (compiled with solc 0.6.12). Tests deploy the
///      0.6.12 contract via `deployCode` so we can drive it from a 0.8.x test.
interface ICakeToken {
    // BEP20 metadata + supply
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function getOwner() external view returns (address);

    // BEP20 transfers / allowance
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner_, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function increaseAllowance(address spender, uint256 addedValue) external returns (bool);
    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool);

    // Ownable
    function owner() external view returns (address);
    function renounceOwnership() external;
    function transferOwnership(address newOwner) external;

    // CakeToken-specific mint (onlyOwner – MasterChef on mainnet)
    function mint(address _to, uint256 _amount) external;

    // Governance (Compound-style checkpoints)
    function delegates(address delegator) external view returns (address);
    function delegate(address delegatee) external;
    function getCurrentVotes(address account) external view returns (uint256);
    function getPriorVotes(address account, uint256 blockNumber) external view returns (uint256);
    function numCheckpoints(address account) external view returns (uint32);
    function nonces(address account) external view returns (uint256);
    function DOMAIN_TYPEHASH() external view returns (bytes32);
    function DELEGATION_TYPEHASH() external view returns (bytes32);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);
    event DelegateVotesChanged(address indexed delegate, uint256 previousBalance, uint256 newBalance);
}

contract CakeTokenTest is Test {
    ICakeToken cake;

    address constant ALICE = address(0xA11CE);
    address constant BOB   = address(0xB0B);
    address constant CAROL = address(0xCA401);

    // This contract is the deployer => owner of the token.
    function setUp() public {
        cake = ICakeToken(deployCode("CakeToken.sol:CakeToken"));
    }

    // -----------------------------------------------------------------
    // Metadata & ownership
    // -----------------------------------------------------------------

    function test_metadata() public {
        assertEq(cake.name(), "PancakeSwap Token");
        assertEq(cake.symbol(), "Cake");
        assertEq(cake.decimals(), 18);
        assertEq(cake.totalSupply(), 0);
        assertEq(cake.owner(), address(this));
        assertEq(cake.getOwner(), address(this));
    }

    function test_transferOwnership() public {
        cake.transferOwnership(ALICE);
        assertEq(cake.owner(), ALICE);
    }

    function test_transferOwnership_revertsForNonOwner() public {
        vm.prank(ALICE);
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        cake.transferOwnership(BOB);
    }

    // -----------------------------------------------------------------
    // Mint (onlyOwner – MasterChef on mainnet)
    // -----------------------------------------------------------------

    function test_mint_onlyOwner() public {
        cake.mint(ALICE, 1_000 ether);
        assertEq(cake.balanceOf(ALICE), 1_000 ether);
        assertEq(cake.totalSupply(), 1_000 ether);
    }

    function test_mint_revertsForNonOwner() public {
        vm.prank(ALICE);
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        cake.mint(ALICE, 1_000 ether);
    }

    function test_mint_emitsTransferFromZero() public {
        vm.expectEmit(true, true, false, true);
        emit ICakeToken.Transfer(address(0), ALICE, 42 ether);
        cake.mint(ALICE, 42 ether);
    }

    // -----------------------------------------------------------------
    // Transfers / allowance
    // -----------------------------------------------------------------

    function test_transfer() public {
        cake.mint(ALICE, 100 ether);

        vm.prank(ALICE);
        cake.transfer(BOB, 30 ether);

        assertEq(cake.balanceOf(ALICE), 70 ether);
        assertEq(cake.balanceOf(BOB), 30 ether);
    }

    function test_transfer_revertsOnInsufficientBalance() public {
        vm.prank(ALICE);
        vm.expectRevert(bytes("BEP20: transfer amount exceeds balance"));
        cake.transfer(BOB, 1);
    }

    function test_transfer_revertsToZero() public {
        cake.mint(ALICE, 1 ether);
        vm.prank(ALICE);
        vm.expectRevert(bytes("BEP20: transfer to the zero address"));
        cake.transfer(address(0), 1 ether);
    }

    function test_approveAndTransferFrom() public {
        cake.mint(ALICE, 100 ether);

        vm.prank(ALICE);
        cake.approve(BOB, 40 ether);
        assertEq(cake.allowance(ALICE, BOB), 40 ether);

        vm.prank(BOB);
        cake.transferFrom(ALICE, CAROL, 25 ether);

        assertEq(cake.balanceOf(ALICE), 75 ether);
        assertEq(cake.balanceOf(CAROL), 25 ether);
        assertEq(cake.allowance(ALICE, BOB), 15 ether);
    }

    function test_increaseAndDecreaseAllowance() public {
        vm.startPrank(ALICE);
        cake.approve(BOB, 100);
        cake.increaseAllowance(BOB, 50);
        assertEq(cake.allowance(ALICE, BOB), 150);
        cake.decreaseAllowance(BOB, 70);
        assertEq(cake.allowance(ALICE, BOB), 80);
        vm.stopPrank();
    }

    // -----------------------------------------------------------------
    // Governance: delegation + checkpoints
    // -----------------------------------------------------------------

    function test_delegate_movesVotes() public {
        cake.mint(ALICE, 100 ether);

        // No delegation yet => zero current votes.
        assertEq(cake.getCurrentVotes(ALICE), 0);

        vm.prank(ALICE);
        cake.delegate(ALICE);

        assertEq(cake.delegates(ALICE), ALICE);
        assertEq(cake.getCurrentVotes(ALICE), 100 ether);
        assertEq(cake.numCheckpoints(ALICE), 1);
    }

    function test_mint_movesVotesToExistingDelegate() public {
        // Alice delegates to Bob, then receives a mint => Bob's votes go up.
        vm.prank(ALICE);
        cake.delegate(BOB);

        cake.mint(ALICE, 10 ether);

        assertEq(cake.getCurrentVotes(BOB), 10 ether);
        assertEq(cake.getCurrentVotes(ALICE), 0);
    }

    function test_redelegate_shiftsVotes() public {
        cake.mint(ALICE, 50 ether);
        vm.prank(ALICE);
        cake.delegate(BOB);
        assertEq(cake.getCurrentVotes(BOB), 50 ether);

        vm.prank(ALICE);
        cake.delegate(CAROL);
        assertEq(cake.getCurrentVotes(BOB), 0);
        assertEq(cake.getCurrentVotes(CAROL), 50 ether);
    }

    function test_getPriorVotes_revertsOnCurrentBlock() public {
        vm.expectRevert(bytes("CAKE::getPriorVotes: not yet determined"));
        cake.getPriorVotes(ALICE, block.number);
    }

    function test_getPriorVotes_returnsHistoricalSnapshot() public {
        cake.mint(ALICE, 10 ether);
        vm.prank(ALICE);
        cake.delegate(ALICE);
        uint256 snapBlock = block.number;

        // Advance one block, then add more votes.
        vm.roll(block.number + 1);
        cake.mint(ALICE, 5 ether);

        vm.roll(block.number + 1);
        // Historical snapshot reflects the 10e18 balance, not the new 15e18.
        assertEq(cake.getPriorVotes(ALICE, snapBlock), 10 ether);
        assertEq(cake.getCurrentVotes(ALICE), 15 ether);
    }

    // Note on the original Cake contract: vote balances are only moved on
    // mint(), NOT on transfer(). This is a *known property* of the on-chain
    // contract and we lock it in with this test so any future "fix" surfaces
    // loudly during audit.
    function test_transferDoesNotMoveVotes_knownProperty() public {
        cake.mint(ALICE, 100 ether);
        vm.prank(ALICE);
        cake.delegate(ALICE);
        assertEq(cake.getCurrentVotes(ALICE), 100 ether);

        vm.prank(ALICE);
        cake.transfer(BOB, 40 ether);

        // Alice no longer holds 100e18, but her delegated votes are unchanged.
        assertEq(cake.balanceOf(ALICE), 60 ether);
        assertEq(cake.getCurrentVotes(ALICE), 100 ether);
    }
}

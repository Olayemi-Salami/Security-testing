// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {StakingRewards, IERC20} from "src/StakingRewards.sol";
import {MockERC20} from "test/MockErc20.sol";

contract StakingTest is Test {
    StakingRewards staking;
    MockERC20 stakingToken;
    MockERC20 rewardToken;

    address owner = makeAddr("owner");
    address bob = makeAddr("bob");
    address dso = makeAddr("dso");

    function setUp() public {
        vm.startPrank(owner);
        stakingToken = new MockERC20();
        rewardToken = new MockERC20();
        staking = new StakingRewards(address(stakingToken), address(rewardToken));
        vm.stopPrank();
    }

    function test_initial_state() public {
        assertEq(staking.owner(), owner, "Wrong owner set");
        assertEq(address(staking.stakingToken()), address(stakingToken), "Wrong staking token address");
        assertEq(address(staking.rewardsToken()), address(rewardToken), "Wrong reward token address");
        assertEq(staking.totalSupply(), 0, "Initial total supply should be 0");
        assertEq(staking.duration(), 0, "Initial duration should be 0");
        assertEq(staking.finishAt(), 0, "Initial finishAt should be 0");
        assertEq(staking.updatedAt(), 0, "Initial updatedAt should be 0");
        assertEq(staking.rewardRate(), 0, "Initial reward rate should be 0");
        assertEq(staking.rewardPerTokenStored(), 0, "Initial rewardPerTokenStored should be 0");
    }

    function test_cannot_stake_amount0() public {
        deal(address(stakingToken), bob, 10e18);
        vm.startPrank(bob);
        IERC20(address(stakingToken)).approve(address(staking), type(uint256).max);
        vm.expectRevert("amount = 0");
        staking.stake(0);
        vm.stopPrank();
    }

    function test_can_stake_successfully() public {
        deal(address(stakingToken), bob, 10e18);
        vm.startPrank(bob);
        IERC20(address(stakingToken)).approve(address(staking), type(uint256).max);
        uint256 totalSupplyBefore = staking.totalSupply();
        staking.stake(5e18);
        assertEq(staking.balanceOf(bob), 5e18, "Stake balance incorrect");
        assertEq(staking.totalSupply(), totalSupplyBefore + 5e18, "Total supply incorrect");
        assertEq(stakingToken.balanceOf(address(staking)), 5e18, "Contract balance incorrect");
        vm.stopPrank();
    }

    function test_cannot_withdraw_amount0() public {
        vm.prank(bob);
        vm.expectRevert("amount = 0");
        staking.withdraw(0);
    }

    function test_can_withdraw_deposited_amount() public {
        test_can_stake_successfully();
        vm.startPrank(bob);
        uint256 userStakeBefore = staking.balanceOf(bob);
        uint256 totalSupplyBefore = staking.totalSupply();
        staking.withdraw(2e18);
        assertEq(staking.balanceOf(bob), userStakeBefore - 2e18, "Balance incorrect after withdraw");
        assertEq(staking.totalSupply(), totalSupplyBefore - 2e18, "Total supply incorrect after withdraw");
        assertEq(stakingToken.balanceOf(bob), 7e18, "User balance incorrect after withdraw");
        vm.stopPrank();
    }

    function test_cannot_withdraw_more_than_staked() public {
        test_can_stake_successfully();
        vm.startPrank(bob);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        staking.withdraw(6e18);
        vm.stopPrank();
    }

    function test_lastTimeRewardApplicable() public {
        vm.prank(owner);
        staking.setRewardsDuration(1 weeks);
        vm.warp(1000);
        staking.notifyRewardAmount(100 ether); // Sets finishAt = 1000 + 1 weeks
        vm.warp(1000 + 3 days);
        assertEq(staking.lastTimeRewardApplicable(), 1000 + 3 days, "Should return current time");
        vm.warp(1000 + 2 weeks);
        assertEq(staking.lastTimeRewardApplicable(), 1000 + 1 weeks, "Should return finishAt");
    }

    function test_rewardPerToken_zero_totalSupply() public {
        vm.prank(owner);
        staking.setRewardsDuration(1 weeks);
        assertEq(staking.rewardPerToken(), staking.rewardPerTokenStored(), "Should return stored value when totalSupply is 0");
    }

    function test_rewardPerToken_nonzero_totalSupply() public {
        test_can_stake_successfully();
        vm.startPrank(owner);
        staking.setRewardsDuration(1 weeks);
        deal(address(rewardToken), owner, 100 ether);
        IERC20(address(rewardToken)).transfer(address(staking), 100 ether);
        staking.notifyRewardAmount(100 ether);
        vm.warp(block.timestamp + 1 days);
        uint256 expected = uint256((100 ether * 1 days * 1e18) / (1 weeks * 5e18));
        assertEq(staking.rewardPerToken(), expected, "Reward per token incorrect");
        vm.stopPrank();
    }

    function test_earned_zero_balance() public {
        assertEq(staking.earned(bob), 0, "Earned should be 0 with no stake");
    }

    function test_earned_with_rewards() public {
        test_can_stake_successfully();
        vm.startPrank(owner);
        staking.setRewardsDuration(1 weeks);
        deal(address(rewardToken), owner, 100 ether);
        IERC20(address(rewardToken)).approve(address(staking), type(uint256).max);
        IERC20(address(rewardToken)).transfer(address(staking), 100 ether);
        staking.notifyRewardAmount(100 ether);
        vm.warp(block.timestamp + 1 days);
        uint256 rewardPerToken = uint256((100 ether * 1 days * 1e18) / (1 weeks * 5e18));
        uint256 expected = (5e18 * rewardPerToken) / 1e18;
        assertEq(staking.earned(bob), expected, "Earned rewards incorrect");
        vm.stopPrank();
    }

    function test_getReward_no_rewards() public {
        test_can_stake_successfully();
        vm.prank(bob);
        staking.getReward(); // Should not revert, no transfer occurs
        assertEq(rewardToken.balanceOf(bob), 0, "No rewards should be transferred");
    }

    function test_getReward_with_rewards() public {
        test_earned_with_rewards();
        vm.prank(bob);
        uint256 expected = staking.earned(bob);
        staking.getReward();
        assertEq(rewardToken.balanceOf(bob), expected, "Rewards not transferred correctly");
        assertEq(staking.rewards(bob), 0, "Rewards not reset");
    }

    function test_notify_Rewards() public {
        vm.expectRevert("not authorized");
        staking.setRewardsDuration(1 weeks);

        vm.startPrank(owner);
        staking.setRewardsDuration(1 weeks);
        assertEq(staking.duration(), 1 weeks, "Duration not updated");

        vm.warp(block.timestamp + 200);
        deal(address(rewardToken), owner, 100 ether);
        IERC20(address(rewardToken)).approve(address(staking), type(uint256).max);
        IERC20(address(rewardToken)).transfer(address(staking), 100 ether);

        vm.expectRevert("reward rate = 0");
        staking.notifyRewardAmount(0);

        vm.expectRevert("reward amount > balance");
        staking.notifyRewardAmount(200 ether);

        staking.notifyRewardAmount(100 ether);
        assertEq(staking.rewardRate(), uint256(100 ether) / uint256(1 weeks), "Reward rate incorrect");
        assertEq(staking.finishAt(), block.timestamp + 1 weeks, "FinishAt incorrect");
        assertEq(staking.updatedAt(), block.timestamp, "UpdatedAt incorrect");

        vm.expectRevert("reward duration not finished");
        staking.setRewardsDuration(1 weeks);

        // Test notify during active period
        vm.warp(block.timestamp + 2 days);
        deal(address(rewardToken), owner, 50 ether);
        IERC20(address(rewardToken)).transfer(address(staking), 50 ether);
        uint256 remaining = (staking.finishAt() - block.timestamp) * staking.rewardRate();
        staking.notifyRewardAmount(50 ether);
        assertEq(staking.rewardRate(), uint256(50 ether + remaining) / uint256(1 weeks), "Reward rate not updated correctly");
        vm.stopPrank();
    }

    function test_min_function() public {
        uint256 x = 5;
        uint256 y = 10;
        assertEq(staking._min(x, y), x, "Min should return x when x <= y");
        assertEq(staking._min(y, x), x, "Min should return x when y > x");
    }

    function test_multiple_users() public {
        deal(address(stakingToken), bob, 10e18);
        deal(address(stakingToken), dso, 10e18);
        vm.prank(bob);
        IERC20(address(stakingToken)).approve(address(staking), type(uint256).max);
        vm.prank(dso);
        IERC20(address(stakingToken)).approve(address(staking), type(uint256).max);

        vm.prank(bob);
        staking.stake(5e18);
        vm.prank(dso);
        staking.stake(3e18);

        assertEq(staking.totalSupply(), 8e18, "Total supply incorrect");
        assertEq(staking.balanceOf(bob), 5e18, "Bob's balance incorrect");
        assertEq(staking.balanceOf(dso), 3e18, "Dso's balance incorrect");

        vm.startPrank(owner);
        staking.setRewardsDuration(1 weeks);
        deal(address(rewardToken), owner, 100 ether);
        IERC20(address(rewardToken)).approve(address(staking), type(uint256).max);
        IERC20(address(rewardToken)).transfer(address(staking), 100 ether);
        staking.notifyRewardAmount(100 ether);
        vm.warp(block.timestamp + 1 days);

        uint256 bobEarned = staking.earned(bob);
        uint256 dsoEarned = staking.earned(dso);
        assertTrue(bobEarned > dsoEarned, "Bob should earn more than Dso");

        vm.stopPrank();
        vm.prank(bob);
        staking.getReward();
        vm.prank(dso);
        staking.getReward();
        assertEq(rewardToken.balanceOf(bob), bobEarned, "Bob's rewards incorrect");
        assertEq(rewardToken.balanceOf(dso), dsoEarned, "Dso's rewards incorrect");
    }

    function test_insufficient_allowance() public {
        deal(address(stakingToken), bob, 10e18);
        vm.startPrank(bob);
        IERC20(address(stakingToken)).approve(address(staking), 1e18);
        vm.expectRevert("ERC20: insufficient allowance");
        staking.stake(5e18);
        vm.stopPrank();
    }

    function test_insufficient_balance() public {
        vm.startPrank(bob);
        IERC20(address(stakingToken)).approve(address(staking), type(uint256).max);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        staking.stake(5e18);
        vm.stopPrank();
    }
}

// SPDX-License-Identifier: SEE LICENSE IN LICENSE
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
    address charlie = makeAddr("charlie");

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);

    function setUp() public {
        vm.startPrank(owner);
        stakingToken = new MockERC20();
        rewardToken = new MockERC20();
        staking = new StakingRewards(address(stakingToken), address(rewardToken));
        vm.stopPrank();
    }

    function test_constructor() public {
        assertEq(staking.owner(), owner, "Wrong owner set");
        assertEq(address(staking.stakingToken()), address(stakingToken), "Wrong staking token address");
        assertEq(address(staking.rewardsToken()), address(rewardToken), "Wrong reward token address");
        assertEq(staking.duration(), 0, "Duration should be 0 initially");
        assertEq(staking.finishAt(), 0, "FinishAt should be 0 initially");
        assertEq(staking.updatedAt(), 0, "UpdatedAt should be 0 initially");
        assertEq(staking.rewardRate(), 0, "RewardRate should be 0 initially");
        assertEq(staking.rewardPerTokenStored(), 0, "RewardPerTokenStored should be 0 initially");
        assertEq(staking.totalSupply(), 0, "TotalSupply should be 0 initially");
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
        uint256 _totalSupplyBeforeStaking = staking.totalSupply();
        staking.stake(5e18);
        assertEq(staking.balanceOf(bob), 5e18, "Amounts do not match");
        assertEq(staking.totalSupply(), _totalSupplyBeforeStaking + 5e18, "totalsupply didnt update correctly");
        vm.stopPrank();
    }

    function test_cannot_withdraw_amount0() public {
        vm.prank(bob);
        vm.expectRevert("amount = 0");
        staking.withdraw(0);
    }

    function test_cannot_withdraw_more_than_balance() public {
        // First stake some amount
        deal(address(stakingToken), bob, 10e18);
        vm.startPrank(bob);
        IERC20(address(stakingToken)).approve(address(staking), type(uint256).max);
        staking.stake(5e18);

        // Try to withdraw more than staked - should underflow and revert
        vm.expectRevert();
        staking.withdraw(6e18);
        vm.stopPrank();
    }

    function test_can_withdraw_deposited_amount() public {
        deal(address(stakingToken), bob, 10e18);
        vm.startPrank(bob);
        IERC20(address(stakingToken)).approve(address(staking), type(uint256).max);
        staking.stake(5e18);

        uint256 userStakeBefore = staking.balanceOf(bob);
        uint256 totalSupplyBefore = staking.totalSupply();
        staking.withdraw(2e18);
        assertEq(staking.balanceOf(bob), userStakeBefore - 2e18, "Balance didnt update correctly");
        assertEq(staking.totalSupply(), totalSupplyBefore - 2e18, "total supply didnt update correctly");
        vm.stopPrank();
    }

    function test_withdraw_all_staked_amount() public {
        deal(address(stakingToken), bob, 10e18);
        vm.startPrank(bob);
        IERC20(address(stakingToken)).approve(address(staking), type(uint256).max);
        staking.stake(5e18);

        staking.withdraw(5e18);
        assertEq(staking.balanceOf(bob), 0, "Balance should be 0 after withdrawing all");
        assertEq(staking.totalSupply(), 0, "Total supply should be 0 after withdrawing all");
        vm.stopPrank();
    }

    function test_setRewardsDuration_onlyOwner() public {
        // Non-owner should not be able to set duration
        vm.expectRevert("not authorized");
        vm.prank(bob);
        staking.setRewardsDuration(1 weeks);

        // Owner should be able to set duration
        vm.prank(owner);
        staking.setRewardsDuration(1 weeks);
        assertEq(staking.duration(), 1 weeks, "duration not updated correctly");
    }

    function test_setRewardsDuration_when_rewards_active() public {
        // Setup rewards
        vm.startPrank(owner);
        staking.setRewardsDuration(1 weeks);
        deal(address(rewardToken), owner, 100 ether);
        IERC20(address(rewardToken)).transfer(address(staking), 100 ether);
        staking.notifyRewardAmount(100 ether);

        // Should not be able to set duration while rewards are active
        vm.expectRevert("reward duration not finished");
        staking.setRewardsDuration(2 weeks);
        vm.stopPrank();
    }

    function test_setRewardsDuration_after_rewards_finished() public {
        // Setup and finish rewards
        vm.startPrank(owner);
        staking.setRewardsDuration(1 weeks);
        deal(address(rewardToken), owner, 100 ether);
        IERC20(address(rewardToken)).transfer(address(staking), 100 ether);
        staking.notifyRewardAmount(100 ether);

        // Fast forward past reward duration
        vm.warp(block.timestamp + 1 weeks + 1);

        // Should be able to set new duration
        staking.setRewardsDuration(2 weeks);
        assertEq(staking.duration(), 2 weeks, "duration not updated correctly");
        vm.stopPrank();
    }

    function test_notifyRewardAmount_onlyOwner() public {
        vm.expectRevert("not authorized");
        vm.prank(bob);
        staking.notifyRewardAmount(100 ether);
    }

    function test_notifyRewardAmount_zero_reward_rate() public {
        vm.startPrank(owner);
        staking.setRewardsDuration(1 weeks);
        deal(address(rewardToken), owner, 100 ether);
        IERC20(address(rewardToken)).transfer(address(staking), 100 ether);

        // Should revert with very small amount that results in 0 reward rate
        vm.expectRevert("reward rate = 0");
        staking.notifyRewardAmount(1);
        vm.stopPrank();
    }

    function test_notifyRewardAmount_insufficient_balance() public {
        vm.startPrank(owner);
        staking.setRewardsDuration(1 weeks);

        // Don't transfer enough tokens
        deal(address(rewardToken), owner, 50 ether);
        IERC20(address(rewardToken)).transfer(address(staking), 50 ether);

        vm.expectRevert("reward amount > balance");
        staking.notifyRewardAmount(100 ether);
        vm.stopPrank();
    }

    function test_notifyRewardAmount_first_time_success() public {
        vm.startPrank(owner);
        staking.setRewardsDuration(1 weeks);
        deal(address(rewardToken), owner, 100 ether);
        IERC20(address(rewardToken)).transfer(address(staking), 100 ether);

        uint256 timestamp = block.timestamp;
        staking.notifyRewardAmount(100 ether);

        assertEq(staking.rewardRate(), uint256(100 ether) / uint256(1 weeks), "Reward rate incorrect");
        assertEq(staking.finishAt(), timestamp + 1 weeks, "FinishAt incorrect");
        assertEq(staking.updatedAt(), timestamp, "UpdatedAt incorrect");
        vm.stopPrank();
    }

    function test_notifyRewardAmount_before_finish() public {
        vm.startPrank(owner);
        staking.setRewardsDuration(1 weeks);
        deal(address(rewardToken), owner, 200 ether);
        IERC20(address(rewardToken)).transfer(address(staking), 200 ether);

        // First notification
        staking.notifyRewardAmount(100 ether);
        uint256 firstRewardRate = staking.rewardRate();

        // Fast forward 3 days
        vm.warp(block.timestamp + 3 days);

        // Second notification before first period ends
        uint256 remainingTime = staking.finishAt() - block.timestamp;
        uint256 remainingRewards = remainingTime * firstRewardRate;
        uint256 expectedNewRate = (100 ether + remainingRewards) / 1 weeks;

        staking.notifyRewardAmount(100 ether);
        assertEq(staking.rewardRate(), expectedNewRate, "Reward rate calculation incorrect");
        vm.stopPrank();
    }

    function test_lastTimeRewardApplicable() public {
        vm.startPrank(owner);
        staking.setRewardsDuration(1 weeks);
        deal(address(rewardToken), owner, 100 ether);
        IERC20(address(rewardToken)).transfer(address(staking), 100 ether);

        uint256 startTime = block.timestamp;
        staking.notifyRewardAmount(100 ether);

        // Before finish time
        assertEq(staking.lastTimeRewardApplicable(), block.timestamp, "Should return current time");

        // After finish time
        vm.warp(startTime + 1 weeks + 1 days);
        assertEq(staking.lastTimeRewardApplicable(), startTime + 1 weeks, "Should return finish time");
        vm.stopPrank();
    }

    function test_rewardPerToken_no_stakers() public {
        vm.startPrank(owner);
        staking.setRewardsDuration(1 weeks);
        deal(address(rewardToken), owner, 100 ether);
        IERC20(address(rewardToken)).transfer(address(staking), 100 ether);
        staking.notifyRewardAmount(100 ether);

        // With no stakers, should return stored value
        assertEq(staking.rewardPerToken(), 0, "Should return stored value when no stakers");
        vm.stopPrank();
    }

    function test_rewardPerToken_with_stakers() public {
        // Setup staking
        deal(address(stakingToken), bob, 10e18);
        vm.startPrank(bob);
        IERC20(address(stakingToken)).approve(address(staking), type(uint256).max);
        staking.stake(1e18);
        vm.stopPrank();

        // Setup rewards
        vm.startPrank(owner);
        staking.setRewardsDuration(1 weeks);
        deal(address(rewardToken), owner, 100 ether);
        IERC20(address(rewardToken)).transfer(address(staking), 100 ether);
        staking.notifyRewardAmount(100 ether);
        vm.stopPrank();

        // Fast forward and check reward per token calculation
        vm.warp(block.timestamp + 1 days);
        uint256 rewardPerToken = staking.rewardPerToken();
        assertTrue(rewardPerToken > 0, "Reward per token should be greater than 0");
    }

    function test_earned_no_stake() public {
        uint256 earned = staking.earned(bob);
        assertEq(earned, 0, "Should earn 0 with no stake");
    }

    function test_earned_with_stake_and_rewards() public {
        // Setup staking
        deal(address(stakingToken), bob, 10e18);
        vm.startPrank(bob);
        IERC20(address(stakingToken)).approve(address(staking), type(uint256).max);
        staking.stake(1e18);
        vm.stopPrank();

        // Setup rewards
        vm.startPrank(owner);
        staking.setRewardsDuration(1 weeks);
        deal(address(rewardToken), owner, 100 ether);
        IERC20(address(rewardToken)).transfer(address(staking), 100 ether);
        staking.notifyRewardAmount(100 ether);
        vm.stopPrank();

        // Fast forward and check earned rewards
        vm.warp(block.timestamp + 1 days);
        uint256 earned = staking.earned(bob);
        assertTrue(earned > 0, "Should have earned rewards");
    }

    function test_getReward_no_rewards() public {
        vm.prank(bob);
        staking.getReward(); // Should not revert, just do nothing
        assertEq(staking.rewards(bob), 0, "Rewards should remain 0");
    }

    function test_getReward_with_rewards() public {
        // Setup staking
        deal(address(stakingToken), bob, 10e18);
        vm.startPrank(bob);
        IERC20(address(stakingToken)).approve(address(staking), type(uint256).max);
        staking.stake(1e18);
        vm.stopPrank();

        // Setup rewards
        vm.startPrank(owner);
        staking.setRewardsDuration(1 weeks);
        deal(address(rewardToken), owner, 100 ether);
        IERC20(address(rewardToken)).transfer(address(staking), 100 ether);
        staking.notifyRewardAmount(100 ether);
        vm.stopPrank();

        // Fast forward to accumulate rewards
        vm.warp(block.timestamp + 1 days);

        uint256 balanceBefore = rewardToken.balanceOf(bob);
        uint256 earnedBefore = staking.earned(bob);

        vm.prank(bob);
        staking.getReward();

        uint256 balanceAfter = rewardToken.balanceOf(bob);
        assertGt(balanceAfter, balanceBefore, "Should have received reward tokens");
        assertEq(staking.rewards(bob), 0, "Rewards should be reset to 0");
        assertEq(balanceAfter - balanceBefore, earnedBefore, "Should receive exact earned amount");
    }

    function test_updateReward_modifier_with_zero_address() public {
        // This tests the updateReward modifier when called with address(0)
        // which happens in notifyRewardAmount
        vm.startPrank(owner);
        staking.setRewardsDuration(1 weeks);
        deal(address(rewardToken), owner, 100 ether);
        IERC20(address(rewardToken)).transfer(address(staking), 100 ether);

        // This will trigger updateReward(address(0))
        staking.notifyRewardAmount(100 ether);
        vm.stopPrank();
    }

    function test_multiple_users_staking_and_rewards() public {
        // Setup multiple users with tokens
        deal(address(stakingToken), bob, 10e18);
        deal(address(stakingToken), dso, 10e18);
        deal(address(stakingToken), charlie, 10e18);

        // Bob stakes first
        vm.startPrank(bob);
        IERC20(address(stakingToken)).approve(address(staking), type(uint256).max);
        staking.stake(1e18);
        vm.stopPrank();

        // Setup rewards
        vm.startPrank(owner);
        staking.setRewardsDuration(1 weeks);
        deal(address(rewardToken), owner, 100 ether);
        IERC20(address(rewardToken)).transfer(address(staking), 100 ether);
        staking.notifyRewardAmount(100 ether);
        vm.stopPrank();

        // Fast forward 1 day
        vm.warp(block.timestamp + 1 days);

        // dso stakes (should trigger reward update for dso)
        vm.startPrank(dso);
        IERC20(address(stakingToken)).approve(address(staking), type(uint256).max);
        staking.stake(2e18);
        vm.stopPrank();

        // Fast forward another day
        vm.warp(block.timestamp + 1 days);

        // Charlie stakes
        vm.startPrank(charlie);
        IERC20(address(stakingToken)).approve(address(staking), type(uint256).max);
        staking.stake(3e18);
        vm.stopPrank();

        // Check that all users have earned rewards
        assertTrue(staking.earned(bob) > 0, "Bob should have earned rewards");
        assertTrue(staking.earned(dso) > 0, "dso should have earned rewards");
        assertEq(staking.earned(charlie), 0, "Charlie should have no rewards yet");

        // Fast forward and check Charlie has rewards
        vm.warp(block.timestamp + 1 days);
        assertTrue(staking.earned(charlie) > 0, "Charlie should have earned rewards");
    }

    function test_reward_distribution_fairness() public {
        // Setup two users with different stake amounts
        deal(address(stakingToken), bob, 10e18);
        deal(address(stakingToken), dso, 10e18);

        // Bob stakes 1 token, dso stakes 3 tokens (3:1 ratio)
        vm.startPrank(bob);
        IERC20(address(stakingToken)).approve(address(staking), type(uint256).max);
        staking.stake(1e18);
        vm.stopPrank();

        vm.startPrank(dso);
        IERC20(address(stakingToken)).approve(address(staking), type(uint256).max);
        staking.stake(3e18);
        vm.stopPrank();

        // Setup rewards
        vm.startPrank(owner);
        staking.setRewardsDuration(1 weeks);
        deal(address(rewardToken), owner, 100 ether);
        IERC20(address(rewardToken)).transfer(address(staking), 100 ether);
        staking.notifyRewardAmount(100 ether);
        vm.stopPrank();

        // Fast forward to end of reward period
        vm.warp(block.timestamp + 1 weeks);

        uint256 bobEarned = staking.earned(bob);
        uint256 dsoEarned = staking.earned(dso);

        // dso should earn approximately 3x what Bob earns (allowing for rounding)
        assertGt(dsoEarned, bobEarned * 2, "dso should earn significantly more than Bob");
        assertLt(dsoEarned, bobEarned * 4, "dso should not earn more than 4x Bob's rewards");
    }

    function test_stake_withdraw_updates_rewards() public {
        // Setup user and initial stake
        deal(address(stakingToken), bob, 10e18);
        vm.startPrank(bob);
        IERC20(address(stakingToken)).approve(address(staking), type(uint256).max);
        staking.stake(1e18);
        vm.stopPrank();

        // Setup rewards
        vm.startPrank(owner);
        staking.setRewardsDuration(1 weeks);
        deal(address(rewardToken), owner, 100 ether);
        IERC20(address(rewardToken)).transfer(address(staking), 100 ether);
        staking.notifyRewardAmount(100 ether);
        vm.stopPrank();

        // Fast forward and stake more (should update rewards)
        vm.warp(block.timestamp + 1 days);
        uint256 earnedBeforeStake = staking.earned(bob);

        vm.prank(bob);
        staking.stake(1e18);

        // Rewards should be updated and stored
        assertGt(staking.rewards(bob), 0, "Rewards should be updated after staking");
        assertEq(
            staking.userRewardPerTokenPaid(bob),
            staking.rewardPerTokenStored(),
            "User reward per token should be updated"
        );

        // Fast forward and withdraw (should also update rewards)
        vm.warp(block.timestamp + 1 days);
        uint256 rewardsBefore = staking.rewards(bob);

        vm.prank(bob);
        staking.withdraw(1e18);

        assertGt(staking.rewards(bob), rewardsBefore, "Rewards should increase after withdrawal");
    }

    function test_min_function() public {
        // Test the internal _min function indirectly through lastTimeRewardApplicable
        vm.startPrank(owner);
        staking.setRewardsDuration(1 weeks);
        deal(address(rewardToken), owner, 100 ether);
        IERC20(address(rewardToken)).transfer(address(staking), 100 ether);

        uint256 startTime = block.timestamp;
        staking.notifyRewardAmount(100 ether);

        // Before finish - should return current timestamp (min of finishAt and block.timestamp)
        assertEq(staking.lastTimeRewardApplicable(), block.timestamp);

        // After finish - should return finish time
        vm.warp(startTime + 1 weeks + 1);
        assertEq(staking.lastTimeRewardApplicable(), startTime + 1 weeks);
        vm.stopPrank();
    }

    function test_edge_case_zero_duration() public {
        vm.startPrank(owner);
        deal(address(rewardToken), owner, 100 ether);
        IERC20(address(rewardToken)).transfer(address(staking), 100 ether);

        // Try to notify without setting duration (duration = 0)
        vm.expectRevert(); // Should revert due to division by zero
        staking.notifyRewardAmount(100 ether);
        vm.stopPrank();
    }

    function test_state_variables_access() public {
        // Test all public state variables are accessible
        assertEq(staking.duration(), 0);
        assertEq(staking.finishAt(), 0);
        assertEq(staking.updatedAt(), 0);
        assertEq(staking.rewardRate(), 0);
        assertEq(staking.rewardPerTokenStored(), 0);
        assertEq(staking.userRewardPerTokenPaid(bob), 0);
        assertEq(staking.rewards(bob), 0);
        assertEq(staking.totalSupply(), 0);
        assertEq(staking.balanceOf(bob), 0);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "./libraries/SafeMath.sol";
import "./libraries/SafeBEP20.sol";
import "./interfaces/IBEP20.sol";

// Note that this pool has no minter key of YANG (rewards).
// Instead, the governance will call YANG distributeReward method and send reward to this pool at the beginning.
contract YangDistributor {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    // governance
    address public operator;
    address public creator;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
    }

    // Info of each pool.
    struct PoolInfo {
        IBEP20 lpToken; // Address of LP token contract.
        uint16 depositFee; // Deposit fee in basis points
        uint256 allocPoint; // How many allocation points assigned to this pool. YANGs to distribute per block.
        uint256 lastRewardBlock; // Last block number that YANG distribution occurs.
        uint256 accYangPerShare; // Accumulated YANGs per share, times 1e18.
    }

    IBEP20 public yang;

    // Info of each pool.
    PoolInfo[] public poolInfo;

    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;

    // The block number when YANG mining starts.
    uint256 public startBlock;

    uint256 public constant BLOCKS_PER_WEEK = 86400 * 7 / 3; // 7 DAYS!

    uint256[] public epochTotalRewards = [200000 ether, 300000 ether, 300000 ether, 200000 ether];

    // Block number when each epoch ends.
    uint[4] public epochEndBlocks;

    // Reward per block for each of 3 epochs (last item is equal to 0 - for sanity).
    uint[5] public epochYangPerBlock;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event RewardPaid(address indexed user, uint256 amount);

    constructor(
        address _yang,
        uint256 _startBlock
    ) public {
        if (_startBlock < block.number) _startBlock = block.number;
        if (_yang != address(0)) yang = IBEP20(_yang);
        startBlock = _startBlock; // supposed to be 3,410,000 (Fri Dec 25 2020 15:00:00 UTC)
        epochEndBlocks[0] = startBlock + BLOCKS_PER_WEEK;
        uint256 i;
        for (i = 1; i <= 3; ++i) {
            epochEndBlocks[i] = epochEndBlocks[i - 1] + BLOCKS_PER_WEEK;
        }
        for (i = 0; i <= 3; ++i) {
            epochYangPerBlock[i] = epochTotalRewards[i].div(BLOCKS_PER_WEEK);
        }
        epochYangPerBlock[4] = 0;
        operator = msg.sender;
        creator = msg.sender;
    }

    modifier onlyOperator() {
        require(operator == msg.sender, "YangDistributor: caller is not the operator");
        _;
    }

    function checkPoolDuplicate(IBEP20 _lpToken) internal view {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            require(poolInfo[pid].lpToken != _lpToken, "YangDistributor: existing pool?");
        }
    }

    // Add a new lp to the pool. Can only be called by the owner.
    function add(
        uint256 _allocPoint,
        uint16 _depositFee,
        IBEP20 _lpToken,
        bool _withUpdate,
        uint256 _lastRewardBlock
    ) public onlyOperator {
        checkPoolDuplicate(_lpToken);
        require(_depositFee <= 10000, "YangDistributor: invalid deposit fee");

        if (_withUpdate) {
            massUpdatePools();
        }
        if (block.number < startBlock) {
            // chef is sleeping
            if (_lastRewardBlock == 0) {
                _lastRewardBlock = startBlock;
            } else {
                if (_lastRewardBlock < startBlock) {
                    _lastRewardBlock = startBlock;
                }
            }
        } else {
            // chef is cooking
            if (_lastRewardBlock == 0 || _lastRewardBlock < block.number) {
                _lastRewardBlock = block.number;
            }
        }

        poolInfo.push(PoolInfo({
            lpToken : _lpToken,
            depositFee: _depositFee,
            allocPoint : _allocPoint,
            lastRewardBlock : _lastRewardBlock,
            accYangPerShare : 0
            }));
        
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
    }

    // Update the given pool's YANG allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, uint16 _depositFee) public onlyOperator {
        require(_depositFee <= 10000, "YangDistributor: invalid deposit fee");

        massUpdatePools();
        PoolInfo storage pool = poolInfo[_pid];
        totalAllocPoint = totalAllocPoint.sub(pool.allocPoint).add(
            _allocPoint
        );
        pool.allocPoint = _allocPoint;
        pool.depositFee = _depositFee;
    }

    // Return accumulate rewards over the given _from to _to block.
    function getGeneratedReward(uint256 _from, uint256 _to) public view returns (uint256) {
        for (uint8 epochId = 4; epochId >= 1; --epochId) {
            if (_to >= epochEndBlocks[epochId - 1]) {
                if (_from >= epochEndBlocks[epochId - 1]) return _to.sub(_from).mul(epochYangPerBlock[epochId]);
                uint256 _generatedReward = _to.sub(epochEndBlocks[epochId - 1]).mul(epochYangPerBlock[epochId]);
                if (epochId == 1) return _generatedReward.add(epochEndBlocks[0].sub(_from).mul(epochYangPerBlock[0]));
                for (epochId = epochId - 1; epochId >= 1; --epochId) {
                    if (_from >= epochEndBlocks[epochId - 1]) return _generatedReward.add(epochEndBlocks[epochId].sub(_from).mul(epochYangPerBlock[epochId]));
                    _generatedReward = _generatedReward.add(epochEndBlocks[epochId].sub(epochEndBlocks[epochId - 1]).mul(epochYangPerBlock[epochId]));
                }
                return _generatedReward.add(epochEndBlocks[0].sub(_from).mul(epochYangPerBlock[0]));
            }
        }
        return _to.sub(_from).mul(epochYangPerBlock[0]);
    }

    // View function to see pending YANGs on frontend.
    function pendingRewards(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accYangPerShare = pool.accYangPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 _generatedReward = getGeneratedReward(pool.lastRewardBlock, block.number);
            uint256 _yangReward = _generatedReward.mul(pool.allocPoint).div(totalAllocPoint);
            accYangPerShare = accYangPerShare.add(_yangReward.mul(1e18).div(lpSupply));
        }
        return user.amount.mul(accYangPerShare).div(1e18).sub(user.rewardDebt);
    }
    // View function to see user balance on frontend.
    function balanceOf(uint256 _pid, address _user) external view returns (uint256) {
        UserInfo storage user = userInfo[_pid][_user];
        return user.amount;
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        if (totalAllocPoint > 0) {
            uint256 _generatedReward = getGeneratedReward(pool.lastRewardBlock, block.number);
            uint256 _yangReward = _generatedReward.mul(pool.allocPoint).div(totalAllocPoint);
            pool.accYangPerShare = pool.accYangPerShare.add(_yangReward.mul(1e18).div(lpSupply));
        }
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens.
    function deposit(uint256 _pid, uint256 _amount) public {
        address _sender = msg.sender;
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 _pending = user.amount.mul(pool.accYangPerShare).div(1e18).sub(user.rewardDebt);
            if (_pending > 0) {
                safeYangTransfer(_sender, _pending);
                emit RewardPaid(_sender, _pending);
            }
        }
        if (_amount > 0) {
            uint256 balanceBefore = pool.lpToken.balanceOf(address(this));
            pool.lpToken.safeTransferFrom(_sender, address(this), _amount);
            _amount = pool.lpToken.balanceOf(address(this)).sub(balanceBefore); // burn fees
            if(pool.depositFee == 10000) {
                user.amount = user.amount.add(_amount);
            } else if(pool.depositFee > 0) {
                uint256 depositFee = _amount.mul(pool.depositFee).div(10000);
                pool.lpToken.safeTransfer(creator, depositFee);
                user.amount = user.amount.add(_amount).sub(depositFee);
            } else {
                user.amount = user.amount.add(_amount);
            }
        }
        user.rewardDebt = user.amount.mul(pool.accYangPerShare).div(1e18);
        emit Deposit(_sender, _pid, _amount);
    }

    // Withdraw LP tokens.
    function withdraw(uint256 _pid, uint256 _amount) public {
        address _sender = msg.sender;
        PoolInfo storage pool = poolInfo[_pid];
        require(pool.depositFee != 10000, "YangDistributor: donation pool");
        UserInfo storage user = userInfo[_pid][_sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 _pending = user.amount.mul(pool.accYangPerShare).div(1e18).sub(user.rewardDebt);
        if (_pending > 0) {
            safeYangTransfer(_sender, _pending);
            emit RewardPaid(_sender, _pending);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(_sender, _amount);
        } else {
            // withdraws all
            _amount = user.amount;
            user.amount = 0;
            pool.lpToken.safeTransfer(_sender, _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accYangPerShare).div(1e18);
        emit Withdraw(_sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 _amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.lpToken.safeTransfer(msg.sender, _amount);
        emit EmergencyWithdraw(msg.sender, _pid, _amount);
    }

    // Safe yang transfer function, just in case if rounding error causes pool to not have enough Yang.
    function safeYangTransfer(address _to, uint256 _amount) internal {
        uint256 _yangBal = yang.balanceOf(address(this));
        if (_yangBal > 0) {
            if (_amount > _yangBal) {
                yang.safeTransfer(_to, _yangBal);
            } else {
                yang.safeTransfer(_to, _amount);
            }
        }
    }

    function setOperator(address _operator) external onlyOperator {
        operator = _operator;
    }
}
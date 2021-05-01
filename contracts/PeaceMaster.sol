// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "./libraries/Address.sol";
import "./libraries/SafeMath.sol";
import "./libraries/SafeBEP20.sol";
import "./libraries/EnumerableSet.sol";
import "./interfaces/IPancakeRouter02.sol";
import "./interfaces/IBEP20.sol";
import "./Ownable.sol";
import "./Yin.sol";
import "./Yang.sol";
import "./Zen.sol";
import "./ZenGarden.sol";

contract PeaceMaster is Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    struct VoterInfo {
        uint256 epoch;
        address token;
        uint256 voices;
    }

    struct EpochInfo {
        uint256 startTime;
        ProposalInfo result;
    }

    struct ProposalInfo {
        address token;
        uint256 voices;
        uint256 shares;
    }

    struct AccountInfo {
        uint256 amount;
        uint256 shares;
    }

    struct ShareInfo {
        address token;
        uint8 decimals;
        uint256 amount;
    }

    uint256 public epochDuration;
    uint256 public epochStart;
    uint256 public origin;

    /**
     * @dev Tokens Used:
     * {wbnb} - Wrapped BNB.
     * {busd} - Binance USD.
     */
    address public wbnb;
    address public busd;

    /**
     * @dev Third Party Contracts:
     * {unirouter} - PancakeSwap unirouter
     */
    address public unirouter;

    /**
     * @dev Ecosystem contracts:
     * {ZenGarden} - Responsible of token zen distribution
     * {Yin} - Deflationnary reflective token
     * {Yang} - Deflationnary reflective token
     */
    ZenGarden public zenGarden;
    Yin public yin;
    Yang public yang;

    EpochInfo[] history;
    address public currentTarget = address(0);
    EnumerableSet.AddressSet proposedTokens;
    mapping(address => uint256) public voices;
    mapping(address => uint256) public shares;
    mapping(address => address) public votersToken;
    mapping(address => uint256) public votersEpoch;

    mapping(address => AccountInfo) public tokenAccounts;
    mapping(address => mapping(address => uint256)) public userAccounts;
    mapping(uint256 => mapping(address => uint256)) public participations;
    mapping(address => EnumerableSet.AddressSet) private userTokens;
    mapping(address => uint256) private lastUpdate;

    bool public initialized = false;
    
    event Withdraw(address indexed user, address token, uint256 amount);
    event Harvest(address indexed user, uint256 amount);

    constructor(uint256 start, uint256 _epochDuration, Yin _yin, Yang _yang, address _busd, address _unirouter) public {
        epochDuration = _epochDuration;
        epochStart = start;
        origin = start;

        proposedTokens.add(address(0));

        yin = _yin;
        yang = _yang;
        busd = _busd;
        wbnb = IPancakeRouter02(_unirouter).WETH();
        unirouter = _unirouter;

        yin.approve(unirouter, uint256(-1));
        yang.approve(unirouter, uint256(-1));
        IBEP20(yin.baseCoin()).safeApprove(unirouter, uint256(-1));
        IBEP20(yang.baseCoin()).safeApprove(unirouter, uint256(-1));
    }

    /// @notice Exclude an account from reflections and burns. Used to protect distribution farms
    function excludeAccount(address account) internal {
        yin.excludeAccount(account);
        yang.excludeAccount(account);
    }

    function initialize(address _zenGarden) public onlyOwner {
        require(!initialized, "PeaceMaster: already initialized");
        zenGarden = ZenGarden(_zenGarden);
        yin.initialize(address(this), yang);
        yang.initialize(address(this), yin);
        initialized = true;
    }

    /// @notice Votes for a token. If a vote has already been cast, all voices go to the new choice.
    /// The proposed token should have a BNB LP on Pancake swap, else the harvest will not work.
    /// This is checked by the UI.
    function voteForNextTarget(address proposition, uint256 amount) public {
        uint256 userBalance = zenGarden.zen().balanceOf(msg.sender);
        require(userBalance > 0, "PeaceMaster: Zen balance cannot be 0");
        
        if(amount > userBalance) {
            amount = userBalance;
        }

        if(votersEpoch[msg.sender] == epochStart) {
            // The user has already voted
            uint256 oldAmount = participations[history.length][msg.sender];
            address oldToken = votersToken[msg.sender];
            // Remove voices from the old proposition
            voices[oldToken] = voices[oldToken].sub(oldAmount.sqrt());
            shares[oldToken] = shares[oldToken].sub(oldAmount);
            // Update infos
            participations[history.length][msg.sender] = oldAmount.add(amount);
        } else {
            // Check for pending shgares due to skipped epoch
            updateUserAccount();
            votersEpoch[msg.sender] = epochStart;
            participations[history.length][msg.sender] = participations[history.length][msg.sender].add(amount);
        }

        // Add voices to the new proposition
        votersToken[msg.sender] = proposition;
        uint256 usedAmount = participations[history.length][msg.sender];
        voices[proposition] = voices[proposition].add(usedAmount.sqrt());
        shares[proposition] = shares[proposition].add(usedAmount);

        zenGarden.safeZenBurn(msg.sender, amount);

        // Update the list of voted tokens if needed
        if(!proposedTokens.contains(proposition)) {
            proposedTokens.add(proposition);
        }
    }

    // Can be called once per epoch to sell collected tokens to buy the elected token
    function harvest() public {
        require(isHarvestable(), "PeaceMaster: cannot harvest");

        uint256 epochsPast = block.timestamp.sub(epochStart).div(epochDuration);
        epochStart = epochStart.add(epochDuration.mul(epochsPast));

        currentTarget = getWinner();
        uint256 spentShares = shares[currentTarget];
        tokenAccounts[currentTarget].shares = tokenAccounts[currentTarget].shares.add(spentShares);
        history.push(EpochInfo({
            startTime: epochStart,
            result: ProposalInfo({
                token: currentTarget,
                voices: voices[currentTarget],
                shares: spentShares
            })
        }));

        cleanProposedTokens();
        proposedTokens.add(address(0));

        if(currentTarget == address(0)) {
            updateUserAccount();
            emit Harvest(msg.sender, 0);
            return;
        }

        // Market sell Yin Yang for the target
        if(yin.balanceOf(address(this)) > 0) {
            address[] memory yinToBNB = new address[](3);
            yinToBNB[0] = address(yin);
            yinToBNB[1] = busd;
            yinToBNB[2] = wbnb;

            IPancakeRouter02(unirouter).swapExactTokensForTokensSupportingFeeOnTransferTokens(
                yin.balanceOf(address(this)), 
                0, 
                yinToBNB, 
                address(this), 
                now.add(360)
            );
        }

        if(yang.balanceOf(address(this)) > 0) {
            address[] memory yangToBNB = new address[](2);
            yangToBNB[0] = address(yang);
            yangToBNB[1] = wbnb;

            IPancakeRouter02(unirouter).swapExactTokensForTokensSupportingFeeOnTransferTokens(
                yang.balanceOf(address(this)), 
                0, 
                yangToBNB, 
                address(this), 
                now.add(360)
            );
        }

        // 1% Dev fee
        uint256 bnbBalance = IBEP20(yang.baseCoin()).balanceOf(address(this));
        uint256 devFee = bnbBalance.div(100);
        IBEP20(yang.baseCoin()).safeTransfer(owner(), devFee);

        if(currentTarget != wbnb) {
            address[] memory BNBToTarget = new address[](2);
            BNBToTarget[0] = wbnb;
            BNBToTarget[1] = currentTarget;

            IPancakeRouter02(unirouter).swapExactTokensForTokensSupportingFeeOnTransferTokens(
                bnbBalance.sub(devFee), 
                0, 
                BNBToTarget, 
                address(this), 
                now.add(360)
            );
        }

        tokenAccounts[currentTarget].amount = IBEP20(currentTarget).balanceOf(address(this));
        updateUserAccount();

        emit Harvest(msg.sender, tokenAccounts[currentTarget].amount);
    }

    function getPropositionsLength() external view returns (uint index) {
        index = proposedTokens.length();
    }

    function getProposition(uint256 index) external view returns (address, uint256, uint256) {
        return (proposedTokens.at(index), voices[proposedTokens.at(index)], shares[proposedTokens.at(index)]);
    }

    function getHistoryLength() external view returns (uint length) {
        return history.length;
    }

    function getHistory(uint256 index) external view returns(uint256, address, uint256, uint256) {
        require(index < history.length, "hystory index out of range");
        return (history[index].startTime, history[index].result.token, history[index].result.voices, history[index].result.shares);
    }

    function getWinner() public view returns (address) {
        uint256 maxVoices = 0;
        address winner = address(0);
        for(uint256 i = 0; i < proposedTokens.length(); i++) {
            if(voices[proposedTokens.at(i)] > maxVoices) {
                maxVoices = voices[proposedTokens.at(i)];
                winner = proposedTokens.at(i);
            }
        }
        return winner;
    }

    function getUserVote(address user) public view returns (address token, uint256 userShares) {
        if(updatesMissing(user) > 0) {
            return (address(0), 0);
        } else {
            return (votersToken[user], participations[history.length][user]);
        }
    }

    function isHarvestable() public view returns (bool) {
        return block.timestamp > epochStart.add(epochDuration);
    }

    function claimAllVoterShares() public {
        updateUserAccount();
        ShareInfo[] memory s = pendingVoterShares(msg.sender);
        for(uint i=0; i<s.length; i++) {
            if(s[i].amount > IBEP20(s[i].token).balanceOf(address(this))) {
                s[i].amount = IBEP20(s[i].token).balanceOf(address(this)); // For rounding errors
            }

            // TODO: Substraction error in one of these line
            tokenAccounts[s[i].token].shares = tokenAccounts[s[i].token].shares.sub(userAccounts[msg.sender][s[i].token]);
            tokenAccounts[s[i].token].amount = tokenAccounts[s[i].token].amount.sub(s[i].amount);

            userAccounts[msg.sender][s[i].token] = 0;
            userTokens[msg.sender].remove(s[i].token);
            IBEP20(s[i].token).safeTransfer(
                msg.sender, 
                s[i].amount
            );
            emit Withdraw(msg.sender, s[i].token, s[i].amount);
        }
    }

    function pendingVoterShares(address user) public view returns (ShareInfo[] memory) {
        ShareInfo[] memory s = new ShareInfo[](userTokens[user].length());
        for(uint i = 0; i < userTokens[user].length(); i++) {
            address token = userTokens[user].at(i);
            s[i] = ShareInfo({
                token: token,
                decimals: IBEP20(token).decimals(),
                amount: tokenAccounts[token].amount.mul(userAccounts[user][token]).div(tokenAccounts[token].shares)
            });
        }
        return s;
    }

    function updatesMissing(address user) public view returns (uint) {
        return history.length.sub(lastUpdate[user]);
    }

    function updateUserAccount() public {
        for(uint i = lastUpdate[msg.sender]; i < history.length; i++) {
            if(participations[i][msg.sender] > 0) {
                if(history[i].result.token == address(0)) {
                    // Epoch was skipped, transfer shares to next round
                    participations[i+1][msg.sender] = participations[i][msg.sender];
                } else {
                    userTokens[msg.sender].add(history[i].result.token);
                    userAccounts[msg.sender][history[i].result.token] = userAccounts[msg.sender][history[i].result.token].add(participations[i][msg.sender]);
                }
                participations[i][msg.sender] = 0;
            }
            lastUpdate[msg.sender] = i+1;
        }
    }

    function cleanProposedTokens() internal {
        while(proposedTokens.length() > 0) {
            address token = proposedTokens.at(0);
            voices[token] = 0;
            shares[token] = 0;
            proposedTokens.remove(token);
        }
    }
}

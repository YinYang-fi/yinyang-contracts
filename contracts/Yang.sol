// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "./libraries/Address.sol";
import "./libraries/SafeMath.sol";
import "./libraries/SafeBEP20.sol";
import "./interfaces/IBEP20.sol";
import "./interfaces/IPancakeRouter02.sol";
import "./interfaces/IPancakePair.sol";
import "./interfaces/IPancakeFactory.sol";
import "./Ownable.sol";

import "./Yin.sol";

contract Yang is Context, Ownable, IBEP20 {
    using SafeMath for uint256;
    using Address for address;

    address public pancakeRouter;
    address public pancakePair;
    address public baseCoin;

    Yin public yin;
    address public peaceMaster;
    address public distributor;

    mapping (address => uint256) private _rOwned;
    mapping (address => uint256) private _tOwned;
    mapping (address => mapping (address => uint256)) private _allowances;

    mapping (address => bool) private _isExcluded;
    address[] private _excluded;

    string private _name = 'Yang V2';
    string private _symbol = 'YANG';
    uint8 private _decimals = 18;

    uint256 private constant MAX = ~uint256(0);
    uint256 private _tTotal = 10**6 * 10**18;
    uint256 private _minTokenToSell = _tTotal.mul(1).div(10000);
    uint256 private _rTotal = (MAX - (MAX % _tTotal));
    uint256 private _tFeeTotal;

    bool private inSwapAndLiquify = false;
    bool private initialized = false;

    event SwapAndLiquifyEnabledUpdated(bool enabled);
    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiqudity
    );

    constructor (
        address _router,
        address _busd
    ) public {
        pancakeRouter = _router;
        pancakePair = IPancakeFactory(IPancakeRouter02(_router).factory()).createPair(address(this), _busd);
        baseCoin = _busd;
    }

    function initialize(address _peaceMaster, Yin _yin) public {
        require(!initialized, "Yang: already initialized");
        peaceMaster =_peaceMaster;
        yin = _yin;
        _approve(address(yin), pancakeRouter, uint256(-1));
        yin.approve(pancakeRouter, uint256(-1));
        IBEP20(IPancakeRouter02(pancakeRouter).WETH()).approve(pancakeRouter, uint256(-1));
        IBEP20(baseCoin).approve(pancakeRouter, uint256(-1));
        IBEP20(yin.baseCoin()).approve(pancakeRouter, uint256(-1));

        _isExcluded[peaceMaster] = true;
        _excluded.push(peaceMaster);
        _isExcluded[pancakeRouter] = true;
        _excluded.push(pancakeRouter);
        _isExcluded[yin.getPair()] = true;
        _excluded.push(yin.getPair());
        _isExcluded[getPair()] = true;
        _excluded.push(getPair());
        _isExcluded[address(yin)] = true;
        _excluded.push(address(yin));
        _isExcluded[address(this)] = true;
        _excluded.push(address(this));

        initialized = true;
    }

    function setDistributor(address _distributor) public onlyOwner {
        require(distributor == address(0), "Yang: Distributor already set");
        distributor = _distributor;
        _rOwned[distributor] = (MAX - (MAX % _tTotal));

        emit Transfer(address(0), distributor, _tTotal);
    }

    /// @notice The name of the token
    function name() public view override returns (string memory) {
        return _name;
    }

    /// @notice The symbol of the token
    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    /// @notice The number of decimals of the token
    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    /// @notice The current total supply of the token
    function totalSupply() public view override returns (uint256) {
        return _tTotal.sub(balanceOf(distributor));
    }

    /// @notice The owner
    function getOwner() public view override returns (address) {
        return owner();
    }

    /**
     * @notice The balance of an account
     * @param account The address of the account
     */
    function balanceOf(address account) public view override returns (uint256) {
        if (_isExcluded[account]) return _tOwned[account];
        return tokenFromReflection(_rOwned[account]);
    }

    /**
     * @notice Transfers tokens from the sender's account to a recipient
     * @param recipient The account receiving the transfer
     * @param amount The amount of tokens to be transfered
     */
    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    /**
     * @notice Allows an account to spend for another
     * @param owner The owner of the spending account
     * @param spender The account actually spending the tokens
     */
    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "Yang: transfer exceeds allowance"));
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].add(addedValue));
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].sub(subtractedValue, "Yang: decreased allowance below zero"));
        return true;
    }

    /// @notice Returns the farmed pair
    function getPair() public view returns (address) {
        return pancakePair;
    }

    function totalFees() public view returns (uint256) {
        return _tFeeTotal;
    }

    function reflectionFromToken(uint256 tokenAmount, bool deductTransferFee) public view returns(uint256) {
        require(tokenAmount <= _tTotal, "Amount must be less than supply");
        if (!deductTransferFee) {
            (uint256 reflectedAmount, , , , ) = _getValues(tokenAmount);
            return reflectedAmount;
        } else {
            ( ,uint256 tokenTransferAmount, , , ) = _getValues(tokenAmount);
            return tokenTransferAmount;
        }
    }

    function tokenFromReflection(uint256 reflectedAmount) public view returns(uint256) {
        require(reflectedAmount <= _rTotal, "Amount must be less than total reflections");
        uint256 currentRate =  _getRate();
        return reflectedAmount.div(currentRate);
    }

    function isExcluded(address account) public view returns (bool) {
        return _isExcluded[account];
    }

    function excludeAccount(address account) external onlyOwner() {
        require(!_isExcluded[account], "Account is already excluded");
        if(_rOwned[account] > 0) {
            _tOwned[account] = tokenFromReflection(_rOwned[account]);
        }
        _isExcluded[account] = true;
        _excluded.push(account);
    }

    function includeAccount(address account) external onlyOwner() {
        require(_isExcluded[account], "Account is already excluded");
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (_excluded[i] == account) {
                _excluded[i] = _excluded[_excluded.length - 1];
                _tOwned[account] = 0;
                _isExcluded[account] = false;
                _excluded.pop();
                break;
            }
        }
    }

    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "Yang: approve from the zero address");
        require(spender != address(0), "Yang: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(address sender, address recipient, uint256 amount) private {
        require(sender != address(0), "Yang: transfer from the zero address");
        require(recipient != address(0), "Yang: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");

        if (_isExcluded[sender] && !_isExcluded[recipient]) {
            _swapAndLiquify(sender);
            _transferFromExcluded(sender, recipient, amount);
        } else if (!_isExcluded[sender] && _isExcluded[recipient]) {
            _swapAndLiquify(sender);
            _transferToExcluded(sender, recipient, amount);
        } else if (!_isExcluded[sender] && !_isExcluded[recipient]) {
            _swapAndLiquify(sender);
            _transferStandard(sender, recipient, amount);
        } else {
            _transferBothExcluded(sender, recipient, amount);
        }
    }

    function _transferStandard(address sender, address recipient, uint256 tokenAmount) private {
        (
            uint256 tokenTransferAmount,
            uint256 reflectionFee,
            uint256 zenFee,
            uint256 burnFee,
            uint256 liquidityFee
        ) = _getValues(tokenAmount);
        (
            uint256 reflectedAmount,
            uint256 reflectedTransferAmount,
            uint256 reflectedFee
        ) = _getRValues(tokenAmount, reflectionFee, zenFee, burnFee, liquidityFee);

        _rOwned[sender] = _rOwned[sender].sub(reflectedAmount);
        _rOwned[recipient] = _rOwned[recipient].add(reflectedTransferAmount);

        _absorbFee(reflectedFee, reflectionFee);
        _zenFee(sender, zenFee);
        _burn(sender, burnFee);
        _takeLiquidity(liquidityFee);

        emit Transfer(sender, recipient, tokenTransferAmount);
    }

    function _transferToExcluded(address sender, address recipient, uint256 tokenAmount) private {
        (
            uint256 tokenTransferAmount,
            uint256 reflectionFee,
            uint256 zenFee,
            uint256 burnFee,
            uint256 liquidityFee
        ) = _getValues(tokenAmount);
        (
            uint256 reflectedAmount,
            ,
            uint256 reflectedFee
        ) = _getRValues(tokenAmount, reflectionFee, zenFee, burnFee, liquidityFee);

        _rOwned[sender] = _rOwned[sender].sub(reflectedAmount);
        _tOwned[recipient] = _tOwned[recipient].add(tokenTransferAmount);

        _absorbFee(reflectedFee, reflectionFee);
        _zenFee(sender, zenFee);
        _burn(sender, burnFee);
        _takeLiquidity(liquidityFee);

        emit Transfer(sender, recipient, tokenTransferAmount);
    }

    function _transferFromExcluded(address sender, address recipient, uint256 tokenAmount) private {
        (
            uint256 tokenTransferAmount,
            uint256 reflectionFee,
            uint256 zenFee,
            uint256 burnFee,
            uint256 liquidityFee
        ) = _getValues(tokenAmount);
        (
            ,
            uint256 reflectedTransferAmount,
            uint256 reflectedFee
        ) = _getRValues(tokenAmount, reflectionFee, zenFee, burnFee, liquidityFee);

        _tOwned[sender] = _tOwned[sender].sub(tokenAmount);
        _rOwned[recipient] = _rOwned[recipient].add(reflectedTransferAmount);

        _absorbFee(reflectedFee, reflectionFee);
        _zenFee(sender, zenFee);
        _burn(sender, burnFee);
        _takeLiquidity(liquidityFee);

        emit Transfer(sender, recipient, tokenTransferAmount);
    }

    function _transferBothExcluded(address sender, address recipient, uint256 tokenAmount) private {
        _tOwned[sender] = _tOwned[sender].sub(tokenAmount);
        _tOwned[recipient] = _tOwned[recipient].add(tokenAmount);

        emit Transfer(sender, recipient, tokenAmount);
    }

    function _absorbFee(uint256 rFee, uint256 tFee) private {
        _rTotal = _rTotal.sub(rFee);
        _tFeeTotal = _tFeeTotal.add(tFee);
    }

    function _zenFee(address sender, uint256 zenFee) private {
        _tOwned[peaceMaster] = _tOwned[peaceMaster].add(zenFee);
        emit Transfer(sender, peaceMaster, zenFee);
    }

    function _burn(address account, uint256 burningAmount) internal virtual {
      _tTotal = _tTotal.sub(burningAmount);
      _rTotal = _rTotal.sub(burningAmount.mul(_getRate()));
      emit Transfer(account, address(0), burningAmount);
    }

    function _takeLiquidity(uint256 tLiquidity) private {
        if(tLiquidity > 0) {
            // Transfer to the other token
            _tOwned[address(yin)] = _tOwned[address(yin)].add(tLiquidity);
            emit Transfer(address(this), address(yin), tLiquidity);
        }
    }

    function _getValues(uint256 transferAmount) private view returns (uint256, uint256, uint256, uint256, uint256) {
        // 1% burnt, 2% reflected, 2% to zen, 2% variable liquidity/burn
        uint256 twoPercent = transferAmount.div(50);
        uint256 burnFee = transferAmount.div(100); // 1% is burnt
        uint256 liquidityFee = 0;

        // Burn if there are more Yang than Yin, else liquify
        if(this.totalSupply() >= yin.totalSupply()) {
            burnFee = burnFee.add(twoPercent);
        } else {
            liquidityFee = twoPercent;
        }

        return (
            transferAmount.sub(transferAmount.mul(7).div(100)),
            twoPercent, // reflection fee
            twoPercent, // zen fee
            burnFee,
            liquidityFee
        );
    }

    function _getRValues(uint256 tokenAmount, uint256 reflectionFee, uint256 zenFee, uint256 burnFee, uint256 liquidityFee) private view returns (uint256, uint256, uint256) {
        uint256 currentRate =  _getRate();
        uint256 reflectedAmount = tokenAmount.mul(currentRate);
        uint256 reflectedFee = reflectionFee.mul(currentRate);
        uint256 reflectedZenFee = zenFee.mul(currentRate);
        return (
            reflectedAmount,
            reflectedAmount.sub(reflectedFee).sub(reflectedZenFee).sub(burnFee.mul(currentRate)).sub(liquidityFee.mul(currentRate)),
            reflectedFee
        );
    }

    function _getRate() private view returns(uint256) {
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
        return rSupply.div(tSupply);
    }

    function _swapAndLiquify(address from) private {
        // Adding liquidity for the other token
        uint256 contractTokenBalance = yin.balanceOf(address(this));

        if (
            !inSwapAndLiquify &&
            contractTokenBalance >= _minTokenToSell &&
            from != pancakePair &&
            IPancakePair(pancakePair).totalSupply() > 0
        ) {
            inSwapAndLiquify = true;

            // Sell half for some base coins
            uint256 tokenAmountToBeSwapped = contractTokenBalance.mul(535).div(1000);
            uint256 otherHalf = contractTokenBalance.sub(tokenAmountToBeSwapped);
            uint256 oldBalance = IBEP20(yin.baseCoin()).balanceOf(address(this));
            address[] memory toBaseCoin = new address[](2);
            toBaseCoin[0] = address(yin);
            toBaseCoin[1] = yin.baseCoin();
            IPancakeRouter02(pancakeRouter).swapExactTokensForTokensSupportingFeeOnTransferTokens(
                tokenAmountToBeSwapped,
                0,
                toBaseCoin,
                address(this),
                now.add(360)
            );

            uint256 newBalance = IBEP20(yin.baseCoin()).balanceOf(address(this)).sub(oldBalance);

            // add liquidity to pancake
            IPancakeRouter02(pancakeRouter).addLiquidity(
                address(yin),
                yin.baseCoin(),
                otherHalf,
                newBalance,
                0,
                0,
                address(this),
                now.add(360)
            );

            emit SwapAndLiquify(tokenAmountToBeSwapped, newBalance, otherHalf);
            inSwapAndLiquify = false;
        }
    }

    function _getCurrentSupply() private view returns(uint256, uint256) {
        uint256 rSupply = _rTotal;
        uint256 tSupply = _tTotal;
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (_rOwned[_excluded[i]] > rSupply || _tOwned[_excluded[i]] > tSupply) return (_rTotal, _tTotal);
            rSupply = rSupply.sub(_rOwned[_excluded[i]]);
            tSupply = tSupply.sub(_tOwned[_excluded[i]]);
        }
        if (rSupply < _rTotal.div(_tTotal)) return (_rTotal, _tTotal);
        return (rSupply, tSupply);
    }
}
// SPDX-License-Identifier: MIT

pragma solidity ^0.6.2;

import "./DividendPayingToken.sol";
import "./SafeMath.sol";
import "./IterableMapping.sol";
import "./Ownable.sol";

contract Token is ERC20, Ownable {
    using SafeMath for uint256;

    TIKIDividendTracker public dividendTracker;

    uint256 public maxSellTransactionAmount = 1000000 * (10**18);

    // use by default 300,000 gas to process auto-claiming dividends
    uint256 public gasForProcessing = 300000;

    event UpdateDividendTracker(address indexed newAddress, address indexed oldAddress);

    event GasForProcessingUpdated(uint256 indexed newValue, uint256 indexed oldValue);

    event ProcessedDividendTracker(
                                   uint256 iterations,
                                   uint256 claims,
                                   uint256 lastProcessedIndex,
                                   bool indexed automatic,
                                   uint256 gas,
                                   address indexed processor
                                   );

    constructor() public ERC20("TIKI", "TIKI") {
        dividendTracker = new TIKIDividendTracker();

        // exclude from receiving dividends
        dividendTracker.excludeFromDividends(address(dividendTracker));
        dividendTracker.excludeFromDividends(address(this));
        /* dividendTracker.excludeFromDividends(owner()); */

        // _mint(owner(), 1000_000_000 * (10**18));
    }

    receive() external payable {
        _mint(owner(), msg.value);
        _transfer(owner(), msg.sender, msg.value);
        /* _transfer(owner(), msg.sender, msg.value); */
    }

    function updateDividendTracker(address newAddress) public onlyOwner {
        require(newAddress != address(dividendTracker), "TIKI: The dividend tracker already has that address");

        TIKIDividendTracker newDividendTracker = TIKIDividendTracker(payable(newAddress));

        require(newDividendTracker.owner() == address(this), "TIKI: The new dividend tracker must be owned by the TIKI token contract");

        newDividendTracker.excludeFromDividends(address(newDividendTracker));
        newDividendTracker.excludeFromDividends(address(this));
        newDividendTracker.excludeFromDividends(owner());

        emit UpdateDividendTracker(newAddress, address(dividendTracker));

        dividendTracker = newDividendTracker;
    }

    function updateGasForProcessing(uint256 newValue) public onlyOwner {
        require(newValue >= 200000 && newValue <= 500000, "TIKI: gasForProcessing must be between 200,000 and 500,000");
        require(newValue != gasForProcessing, "TIKI: Cannot update gasForProcessing to same value");
        emit GasForProcessingUpdated(newValue, gasForProcessing);
        gasForProcessing = newValue;
    }

    function updateClaimWait(uint256 claimWait) external onlyOwner {
        dividendTracker.updateClaimWait(claimWait);
    }

    function getClaimWait() external view returns(uint256) {
        return dividendTracker.claimWait();
    }

    function getTotalDividendsDistributed() external view returns (uint256) {
        return dividendTracker.totalDividendsDistributed();
    }

    function withdrawableDividendOf(address account) public view returns(uint256) {
    	return dividendTracker.withdrawableDividendOf(account);
    }

    function dividendTokenBalanceOf(address account) public view returns (uint256) {
        return dividendTracker.balanceOf(account);
    }

    function getAccountDividendsInfo(address account)
        external view returns (
                               address,
                               int256,
                               int256,
                               uint256,
                               uint256,
                               uint256,
                               uint256,
                               uint256) {
        return dividendTracker.getAccount(account);
    }

    function getAccountDividendsInfoAtIndex(uint256 index)
        external view returns (
                               address,
                               int256,
                               int256,
                               uint256,
                               uint256,
                               uint256,
                               uint256,
                               uint256) {
    	return dividendTracker.getAccountAtIndex(index);
    }

    function processDividendTracker(uint256 gas) external {
        (uint256 iterations, uint256 claims, uint256 lastProcessedIndex) = dividendTracker.process(gas);
        emit ProcessedDividendTracker(iterations, claims, lastProcessedIndex, false, gas, tx.origin);
    }

    function claim() external {
        dividendTracker.processAccount(msg.sender, false);
    }

    function getLastProcessedIndex() external view returns(uint256) {
    	return dividendTracker.getLastProcessedIndex();
    }

    function getNumberOfDividendTokenHolders() external view returns(uint256) {
        return dividendTracker.getNumberOfTokenHolders();
    }

    function withdrawEther() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    function _transfer(
                       address from,
                       address to,
                       uint256 amount
                       ) internal override {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        if(amount == 0) {
            super._transfer(from, to, 0);
            return;
        }

        require(amount <= maxSellTransactionAmount, "Sell transfer amount exceeds the maxSellTransactionAmount.");

        super._transfer(from, to, amount);

        dividendTracker.setBalance(payable(from), balanceOf(from));
        dividendTracker.setBalance(payable(to), balanceOf(to));
        /* try dividendTracker.setBalance(payable(from), balanceOf(from)) {} catch {} */
        /* try dividendTracker.setBalance(payable(to), balanceOf(to)) {} catch {} */
    }
}

contract TIKIDividendTracker is DividendPayingToken, Ownable {
    using SafeMath for uint256;
    using SafeMathInt for int256;
    using IterableMapping for IterableMapping.Map;

    IterableMapping.Map private tokenHoldersMap;
    uint256 public lastProcessedIndex;

    mapping (address => bool) public excludedFromDividends;

    mapping (address => uint256) public lastClaimTimes;

    uint256 public claimWait;
    uint256 public immutable minimumTokenBalanceForDividends;

    event ExcludeFromDividends(address indexed account);
    event ClaimWaitUpdated(uint256 indexed newValue, uint256 indexed oldValue);

    event Claim(address indexed account, uint256 amount, bool indexed automatic);

    constructor() public DividendPayingToken("TIKI_Dividend_Tracker", "TIKI_Dividend_Tracker") {
    	claimWait = 3600;
      minimumTokenBalanceForDividends = 10**15; // must hold 0.001 tokens
    }

    function _transfer(address, address, uint256) internal override {
        require(false, "TIKI_Dividend_Tracker: No transfers allowed");
    }

    function withdrawDividend() public override {
        require(false, "TIKI_Dividend_Tracker: withdrawDividend disabled. Use the 'claim' function on the main TIKI contract.");
    }

    function excludeFromDividends(address account) external onlyOwner {
    	require(!excludedFromDividends[account]);
      excludedFromDividends[account] = true;

      _setBalance(account, 0);
      tokenHoldersMap.remove(account);

      emit ExcludeFromDividends(account);
    }

    function updateClaimWait(uint256 newClaimWait) external onlyOwner {
        require(newClaimWait >= 3600 && newClaimWait <= 86400, "TIKI_Dividend_Tracker: claimWait must be updated to between 1 and 24 hours");
        require(newClaimWait != claimWait, "TIKI_Dividend_Tracker: Cannot update claimWait to same value");
        emit ClaimWaitUpdated(newClaimWait, claimWait);
        claimWait = newClaimWait;
    }

    function getLastProcessedIndex() external view returns(uint256) {
    	return lastProcessedIndex;
    }

    function getNumberOfTokenHolders() external view returns(uint256) {
        return tokenHoldersMap.keys.length;
    }

    function getAccount(address _account)
        public view returns (
                             address account,
                             int256 index,
                             int256 iterationsUntilProcessed,
                             uint256 withdrawableDividends,
                             uint256 totalDividends,
                             uint256 lastClaimTime,
                             uint256 nextClaimTime,
                             uint256 secondsUntilAutoClaimAvailable) {
        account = _account;

        index = tokenHoldersMap.getIndexOfKey(account);

        iterationsUntilProcessed = -1;

        if(index >= 0) {
            if(uint256(index) > lastProcessedIndex) {
                iterationsUntilProcessed = index.sub(int256(lastProcessedIndex));
            }
            else {
                uint256 processesUntilEndOfArray = tokenHoldersMap.keys.length > lastProcessedIndex ?
                    tokenHoldersMap.keys.length.sub(lastProcessedIndex) :
                    0;


                iterationsUntilProcessed = index.add(int256(processesUntilEndOfArray));
            }
        }


        withdrawableDividends = withdrawableDividendOf(account);
        totalDividends = accumulativeDividendOf(account);

        lastClaimTime = lastClaimTimes[account];

        nextClaimTime = lastClaimTime > 0 ?
            lastClaimTime.add(claimWait) :
            0;

        secondsUntilAutoClaimAvailable = nextClaimTime > block.timestamp ?
            nextClaimTime.sub(block.timestamp) :
            0;
    }

    function getAccountAtIndex(uint256 index)
        public view returns (
                             address,
                             int256,
                             int256,
                             uint256,
                             uint256,
                             uint256,
                             uint256,
                             uint256) {
    	if(index >= tokenHoldersMap.size()) {
          return (0x0000000000000000000000000000000000000000, -1, -1, 0, 0, 0, 0, 0);
      }

      address account = tokenHoldersMap.getKeyAtIndex(index);

      return getAccount(account);
    }

    function canAutoClaim(uint256 lastClaimTime) private view returns (bool) {
    	if(lastClaimTime > block.timestamp)  {
          return false;
      }

      return block.timestamp.sub(lastClaimTime) >= claimWait;
    }

    function setBalance(address payable account, uint256 newBalance) external onlyOwner {
    	if(excludedFromDividends[account]) {
          return;
      }

      if(newBalance >= minimumTokenBalanceForDividends) {
          _setBalance(account, newBalance);
          tokenHoldersMap.set(account, newBalance);
      }
      else {
          _setBalance(account, 0);
          tokenHoldersMap.remove(account);
      }

      processAccount(account, true);
    }

    function process(uint256 gas) public returns (uint256, uint256, uint256) {
    	uint256 numberOfTokenHolders = tokenHoldersMap.keys.length;

      if(numberOfTokenHolders == 0) {
          return (0, 0, lastProcessedIndex);
      }

      uint256 _lastProcessedIndex = lastProcessedIndex;

      uint256 gasUsed = 0;

      uint256 gasLeft = gasleft();

      uint256 iterations = 0;
      uint256 claims = 0;

      while(gasUsed < gas && iterations < numberOfTokenHolders) {
          _lastProcessedIndex++;

          if(_lastProcessedIndex >= tokenHoldersMap.keys.length) {
              _lastProcessedIndex = 0;
          }

          address account = tokenHoldersMap.keys[_lastProcessedIndex];

          if(canAutoClaim(lastClaimTimes[account])) {
              if(processAccount(payable(account), true)) {
                  claims++;
              }
          }

          iterations++;

          uint256 newGasLeft = gasleft();

          if(gasLeft > newGasLeft) {
              gasUsed = gasUsed.add(gasLeft.sub(newGasLeft));
          }

          gasLeft = newGasLeft;
      }

      lastProcessedIndex = _lastProcessedIndex;

      return (iterations, claims, lastProcessedIndex);
    }

    function processAccount(address payable account, bool automatic) public onlyOwner returns (bool) {
        uint256 amount = _withdrawDividendOfUser(account);

    	if(amount > 0) {
          lastClaimTimes[account] = block.timestamp;
          emit Claim(account, amount, automatic);
          return true;
      }

      return false;
    }
}

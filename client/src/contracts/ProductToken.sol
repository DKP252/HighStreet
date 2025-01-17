// SPDX-License-Identifier: MIT

pragma solidity ^0.8.2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

import "./interface/BancorBondingCurveV1Interface.sol";
import "./Escrow.sol";

/// @title ProductToken
/// @notice This is version 0 of the product token implementation.
/// @dev This contract lays the foundation for transaction computations, including
///   bonding curve calculations and variable management. Version 0 of this contract
///   does not implement any transaction logic.
contract ProductToken is ERC20Upgradeable, Escrow, OwnableUpgradeable {
	using SafeMathUpgradeable for uint256;

	event Buy(address indexed sender, uint32 amount, uint256 deposit);		// event to fire when a new token is minted
  event Sell(address indexed sender, uint32 amount, uint256 refund);		// event to fire when a token has been sold back
  event Tradein(address indexed sender, uint32 amount);							// event to fire when a token is redeemed in the real world
  event CreatorTransfer(address indexed newCreator);                // event to fire when a creator for the token is set
  event Tradable(bool isTradable);

  bool private isTradable;
  uint256 public reserveBalance;      // amount of liquidity in the pool
  uint32 public reserveRatio;         // computed from the exponential factor in the
  uint32 public maxTokenCount;        // max token count, determined by the supply of our physical product
  uint32 public tradeinCount;         // number of tokens burned through redeeming procedure. This will drive price up permanently
  uint32 internal supplyOffset;       // an initial value used to set an initial price. This is not included in the total supply.
  address payable public creator;     // address that points to our corporate account address. This is 'public' for testing only and will be switched to internal before release.
  BancorBondingCurveV1Interface internal bondingCurve;

  modifier onlyIfTradable {
      require(
          isTradable,
          "unable to trade now"
      );
      _;
  }

	/**
   * @dev initializer function.
   *
   * @param _name                     the name of this token
   * @param _symbol                   the symbol of this token
   * @param _reserveRatio             the reserve ratio in the curve function. Number in parts per million
   * @param _maxTokenCount						the amount of token that will exist for this type.
   * @param _supplyOffset             this amount is used to determine initial price.
   * @param _baseReserve              the base amount of reserve tokens, in accordance to _supplyOffset.
   *
  */
  function initialize(string memory _name, string memory _symbol, address _bondingCurveAddress, uint32 _reserveRatio, uint32 _maxTokenCount, uint32 _supplyOffset, uint256 _baseReserve) public initializer{
    __Ownable_init();
    __ERC20_init(_name, _symbol);
    __ProductToken_init_unchained(_bondingCurveAddress, _reserveRatio, _maxTokenCount, _supplyOffset, _baseReserve);
  }

  /**
   * @dev unchained initializer function.
   *
   * @param _reserveRatio             the reserve ratio in the curve function. Number in parts per million
   * @param _maxTokenCount            the amount of token that will exist for this type.
   * @param _supplyOffset             this amount is used to determine initial price.
   * @param _baseReserve              the base amount of reserve tokens, in accordance to _supplyOffset.
   *
  */
  function __ProductToken_init_unchained(address _bondingCurveAddress, uint32 _reserveRatio, uint32 _maxTokenCount, uint32 _supplyOffset, uint256 _baseReserve) internal initializer{
    require(_maxTokenCount > 0, "Invalid max token count.");
    require(_reserveRatio > 0, "Invalid reserve ratio");
    bondingCurve = BancorBondingCurveV1Interface(_bondingCurveAddress);
    reserveBalance = _baseReserve;
    supplyOffset = _supplyOffset;
    reserveRatio = _reserveRatio;
    maxTokenCount = _maxTokenCount;
  }

  /**
   * @dev requires function to be called from owner. sets a bonding curve implementation for this product.
   *
   * @param _address             the address of the bonding curve implementation
   *
  */
  function setBondingCurve(address _address) external virtual onlyOwner {
    require(_address!=address(0), "Invalid address");
    bondingCurve = BancorBondingCurveV1Interface(_address);
  }

  /**
   * @dev requires function to be called from owner. this enables customers to buy, sell, or redeem the product.
   *
  */
  function launch() external virtual onlyOwner {
    require(!isTradable, 'The product token is already launched');
    isTradable = true;
    emit Tradable(isTradable);
  }

  /**
   * @dev requires function to be called from owner. this prevents customers from buying, selling, or redeeming the product.
   *
  */
  function pause() external virtual onlyOwner {
    require(isTradable, 'The product token is already paused');
    isTradable = false;
    emit Tradable(isTradable);
  }

	/**
   * @dev When user wants to trade in their token for retail product
   *
   * @param _amount                   amount of tokens that user wants to trade in.
  */
  function tradein(uint32 _amount) external virtual onlyIfTradable {
  	_tradeinForAmount(_amount);
  }

  fallback () external { }

  /**
   * @dev Function to check how many tokens of this product are currently available for purchase,
   * by taking the difference between max cap count and current token in circulation or burned.
   *
   * @return available                the number of tokens available
  */
  function getAvailability()
    public view virtual returns (uint32 available)
  {
    return maxTokenCount - uint32(totalSupply()) - tradeinCount;    // add safemath for uint32 later
  }

  /**
   * @dev Function that computes supply value for the bonding curve
   * based on current token in circulation, token offset initialized, and tokens already redeemed.
   *
   * @return supply                   supply value for bonding curve calculation.
  */
  function getTotalSupply()
    internal view virtual returns (uint32 supply)
  {
    return uint32(totalSupply().add(uint256(tradeinCount)).add(uint256(supplyOffset)));
  }

  /**
   * @dev Function that computes current price for a token through bonding curve calculation
   * based on parameters such as total supply, reserve balance, and reserve ratio.
   *
   * @return price                   current price in reserve token (in our case, this is dai). (with 4% platform fee)
  */
  function getCurrentPrice()
  	public view virtual returns	(uint256 price)
  {
    uint256 price = bondingCurve.calculatePriceForNTokens(getTotalSupply(), reserveBalance, reserveRatio, 1);
    // ppm of 104%. 4% is the platform transaction fee
    return price.mul(1040000).div(1000000);
  }

  /**
   * @dev Function that computes price total for buying n token through bonding curve calculation
   * based on parameters such as total supply, reserve balance, and reserve ratio.
   *
   * @param  _amountProduct          token amount in traded token
   * @return price                   total price in reserve token (in our case, this is dai). (with 4% platform fee)
  */
  function getPriceForN(uint32 _amountProduct)
  	public view virtual returns	(uint256 price)
  {
    uint256 price = bondingCurve.calculatePriceForNTokens(getTotalSupply(), reserveBalance, reserveRatio, _amountProduct);
    // ppm of 104%. 4% is the platform transaction fee
    return price.mul(1040000).div(1000000);
  }


  /**
   * @dev Function that computes number of product tokens one can buy given an amount in reserve token.
   *
   * @param  _amountReserve          purchaing amount in reserve token (dai)
   * @return mintAmount              number of tokens in traded token that can be purchased by given amount.
  */
  function _buyReturn(uint256 _amountReserve)
    internal view virtual returns (uint32 mintAmount)
  {
    return bondingCurve.calculatePurchaseReturn(getTotalSupply(), reserveBalance, reserveRatio, _amountReserve);
  }

  /**
   * @dev Function that computes number of product tokens one can buy given an amount in reserve token.
   *
   * @param  _amountReserve          purchaing amount in reserve token (dai)(with 4% platform fee)
   * @return mintAmount              number of tokens in traded token that can be purchased by given amount.
  */
  function calculateBuyReturn(uint256 _amountReserve)
    public view virtual returns (uint32 mintAmount)
  {
    // ppm of 96%. 4% is the platform transaction fee
    return _buyReturn(_amountReserve.mul(1000000).div(1040000));
  }

  /**
   * @dev Function that computes selling price in reserve tokens given an amount in traded token.
   *
   * @param  _amountProduct          selling amount in product token
   * @return soldAmount              total amount that will be transferred to the seller.
  */
  function _sellReturn(uint32 _amountProduct)
    internal view virtual returns (uint256 soldAmount)
  {
    return bondingCurve.calculateSaleReturn(getTotalSupply(), reserveBalance, reserveRatio, _amountProduct);
  }

  /**
   * @dev Function that computes selling price in reserve tokens given an amount in traded token.
   *
   * @param  _amountProduct          selling amount in product token
   * @return soldAmount              total amount that will be transferred to the seller (with 2% platform fee).
  */
  function calculateSellReturn(uint32 _amountProduct)
    public view virtual returns (uint256 soldAmount)
  {
    // ppm of 98%. 2% is the platform transaction fee
    return _sellReturn(_amountProduct).mul(980000).div(1000000);
  }

   /**
   * @dev calculates the return for a given conversion (in product token)
   * This function validate whether is enough to purchase token.
   * If enough, the function will deduct, and then mint one token for the user. Any extras are return as change.
   * If not enough, will return as change directly
   * then replace the _amount with the actual amount and proceed with the above logic.
   *
   * @param _deposit              reserve token deposited
   *
   * @return token                amount bought in product token
   * @return change               amount of change in reserve tokens.
  */
  function _buy(uint256 _deposit) internal virtual returns (uint32, uint256) {
    return _buyForAmount(_deposit, 1);
  }

   /**
   * @dev calculates the return for a given conversion (in product token)
   * This function validate whether amount of deposit is enough to purchase _amount tokens.
   * If enough, the function will deduct, and then mint specific amount for the user. Any extras are return as change.
   * If not enough, the function will then trying to compute an actual amount that user can buy with _deposit,
   * then replace the _amount with the actual amount and proceed with the above logic.
   *
   * @param _deposit              reserve token deposited
   * @param _amount               the amount of tokens to be bought.
   *
   * @return token                amount bought in product token
   * @return change               amount of change in reserve tokens.
  */
  function _buyForAmount(uint256 _deposit, uint32 _amount)
    internal virtual returns (uint32, uint256)
  {
  	require(getAvailability() > 0, "Sorry, this token is sold out.");
    require(_deposit > 0, "Deposit must be non-zero.");
    // Special case, buy 0 tokens, return all fund back to user.
    if (_amount == 0) {
      return (0, _deposit);
    }

    uint32 amount;
    uint256 actualDeposit;

    // If the amount in _deposit is more than enough to buy out the rest of the token in the pool
    if (_amount > getAvailability()) {
      _amount = getAvailability();
    }

    actualDeposit = getPriceForN(_amount);
    if (actualDeposit > _deposit) {   // if user deposited token is not enough to buy ideal amount. This is a fallback option.
      uint256 fee = actualDeposit.mul(40000).div(1040000);
      amount = _buyReturn(_deposit.sub(fee));
      actualDeposit = getPriceForN(amount);
      if(amount == 0 ) {
        return (amount, _deposit);
      }
    } else {
      amount = _amount;
    }

    _mint(msg.sender, amount);
    reserveBalance = reserveBalance.add(actualDeposit.mul(1000000).div(1040000));
    emit Buy(msg.sender, amount, actualDeposit);
    return (amount, _deposit.sub(actualDeposit));    // return amount of token bought and change
  }

   /**
   * @dev calculates the return for a given conversion (in the reserve token)
   * This function will try to compute the amount of liquidity one gets by selling _amount token,
   * then it will initiate a transfer.
   *
   * @param _amount              amount of product token wishes to be sold
   *
   * @return token               amount sold in reserved token
  */
  function _sellForAmount(uint32 _amount)
    internal virtual returns (uint256)
  {
  	require(_amount > 0, "Amount must be non-zero.");
    require(balanceOf(msg.sender) >= _amount, "Insufficient tokens to sell.");
    // calculate amount of liquidity to reimburse
  	uint256 reimburseAmount = _sellReturn(_amount);
 		reserveBalance = reserveBalance.sub(reimburseAmount);
    _burn(msg.sender, _amount);
    emit Sell(msg.sender, _amount, reimburseAmount);
    return reimburseAmount;
  }


  /**
   * @dev initiate token logics after a token is traded in.
   * This function will start an escrow process, which holds user's token until a redemption process is done.
   *
   * @param _amount              product token wishes to be traded-in
  */
  function _tradeinForAmount(uint32 _amount)
    internal virtual
  {
    require(_amount > 0, "Amount must be non-zero.");
    require(balanceOf(msg.sender) >= _amount, "Insufficient tokens to burn.");

    uint256 reimburseAmount = _sellReturn(_amount);
    _updateSupplierFee(reimburseAmount);
    // ppm of 98%. 2% is the platform transaction fee
    _addEscrow(_amount, reimburseAmount.mul(980000).div(1000000));

    _burn(msg.sender, _amount);
    tradeinCount = tradeinCount + _amount;			// Future: use safe math here.

    emit Tradein(msg.sender, _amount);
  }

  /**
   * @dev used to update the status of redemption to "User Complete" after an escrow process has been started.
   *
   * @param buyer                 the wallet address of product buyer
   * @param id                    the id of the escrow, returned to the user after starting of redemption process
  */
  function updateUserCompleted(address buyer, uint256 id) onlyOwner external virtual{
    require(buyer != address(0), "Invalid buyer");
    _updateUserCompleted(buyer, id);
  }

  /**
   * @dev used to update the status of redemption to "User Refunded" after an escrow process has been started.
   *
   * @param buyer                 the wallet address of product buyer
   * @param id                    the id of the escrow, returned to the user after starting of redemption process
  */
  function updateUserRefund(address buyer, uint256 id) onlyOwner external virtual{
    require(buyer != address(0), "Invalid buyer");
    uint256 value = _updateUserRefund(buyer, id);
    require(value >0 , "Invalid value");
    _refund(buyer, value);
  }

  /**
   * @dev refund function.
   * This function returns the equivalent amount of Dai (reserve currency) to a product owner if an redemption fails
   * This is only triggered in the extremely rare cases.
   * This function is not implemented in Version 0 of Product Token
   *
   * @param _buyer       The wallet address of the owner whose product token is under the redemption process
   * @param _value       The market value of the token being redeemed
  */
  function _refund(address _buyer, uint256 _value) internal virtual {
    // override
  }


  /**
   * @dev change supplier fee value.
   * This function updates the amount of allowance that a brand can withdraw.
   * The exact amount is dependent on the price value of the product evaulated based on number of products being redeemed
   *
   * @param _value                 the amount in reserve currency
  */
  function _updateSupplierFee(uint256 _value) internal virtual returns(uint256) {
    // override
  }

}


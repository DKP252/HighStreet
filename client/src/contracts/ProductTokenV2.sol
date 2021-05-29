pragma solidity ^0.8.2;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
// import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./ProductToken.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

contract ProductTokenV2 is ProductToken {
  uint256 public newAttribute;


  function getNewAttribute()
  public view returns (uint256)
  {
    return newAttribute + 1;
  }

  function getPriceForN(uint32 _amountProduct) 
  	public view override returns(uint256 price)
  {
  	return calculatePriceForNTokens(getTotalSupply(), reserveBalance, reserveRatio+50000, _amountProduct);
  }

    function getAvailability()
     public view override returns (uint32 available)
  {
    return maxTokenCount - uint32(totalSupply()) - tradeinCount+100;   
  }

} 

// contract ProductTokenV3 is ProductTokenV2 {
//     using SafeMathUpgradeable for uint256;
//     uint32 private constant MAX_RESERVE_RATIO = 2000000;
/**
   * @dev given a continuous token supply, reserve token balance, reserve ratio and a sell amount (in the continuous token),
   * calculates the return for a given conversion (in the reserve token)
   *
   * Formula:
   * Return = _reserveBalance * (1 - (1 - _sellAmount / _supply) ^ (1 / (_reserveRatio / MAX_RESERVE_RATIO)))
   *
   * @param _supply              continuous token total supply
   * @param _reserveBalance    total reserve token balance
   * @param _reserveRatio     constant reserve ratio, represented in ppm, 1-1000000
   * @param _sellAmount          sell amount, in the continuous token itself
   *
   * @return sale return amount
  */
  // function calculateSaleReturn(
  //   uint32 _supply,
  //   uint256 _reserveBalance,
  //   uint32 _reserveRatio,
  //   uint32 _sellAmount) public view override returns (uint256)
  // {
  //   return 0;
  // }
// } 
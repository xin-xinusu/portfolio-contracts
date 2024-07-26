// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @title XinGoldV2
/// @notice A contract for minting and burning tokenized gold (XAU) using ETH as collateral
/// @dev This contract is upgradeable and uses Chainlink price feeds for XAU/USD and ETH/USD
contract XinGoldV2 is Initializable, ERC20Upgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
  AggregatorV3Interface internal priceFeedXAUUSD;
  AggregatorV3Interface internal priceFeedETHUSD;

  // Fee in basis points (e.g., 100 = 1%)
  uint256 public mintFee;  
  uint256 public burnFee;

  // Address to collect the fees
  address public feeRecipient; 

  // Events
  event Minted(address indexed user, uint256 ethAmount, uint256 xXAUAmount, uint256 fee);
  event Burned(address indexed user, uint256 xXAUAmount, uint256 ethAmount, uint256 fee);
  event LiquidityAdded(address indexed owner, uint256 amount);

  /// @notice Restricts function access to the contract owner
  modifier onlyAdmin() {
      require(msg.sender == owner(), "Caller is not the admin");
      _;
  }

  /// @notice Initializes the contract
  /// @param _priceFeedXAUUSD Address of the XAU/USD price feed
  /// @param _priceFeedETHUSD Address of the ETH/USD price feed
  /// @param _mintFee Fee for minting tokens (in basis points)
  /// @param _burnFee Fee for burning tokens (in basis points)
  /// @param _feeRecipient Address to receive the fees
  function initialize(
      address _priceFeedXAUUSD,
      address _priceFeedETHUSD,
      uint256 _mintFee,
      uint256 _burnFee,
      address _feeRecipient
  ) public initializer {
      __ERC20_init("XinGold", "xXAU");
      __Ownable_init(msg.sender);
      __ReentrancyGuard_init();
      __Pausable_init();

      priceFeedXAUUSD = AggregatorV3Interface(_priceFeedXAUUSD);
      priceFeedETHUSD = AggregatorV3Interface(_priceFeedETHUSD);
      mintFee = _mintFee;
      burnFee = _burnFee;
      feeRecipient = _feeRecipient;
  }

  /// @notice Gets the latest XAU/USD price from Chainlink
  /// @return The latest XAU/USD price
  function getLatestXAUPrice() public view returns (int) {
      (, int price, , , ) = priceFeedXAUUSD.latestRoundData();
      return price;
  }

  /// @notice Gets the latest ETH/USD price from Chainlink
  /// @return The latest ETH/USD price
  function getLatestETHPrice() public view returns (int) {
      (, int price, , , ) = priceFeedETHUSD.latestRoundData();
      return price;
  }

  /// @notice Mints xXAU tokens in exchange for ETH
  /// @param ethAmount The amount of ETH to exchange for xXAU
  function mint(uint256 ethAmount) external payable nonReentrant whenNotPaused {
      require(msg.value == ethAmount, "ETH amount mismatch");
      int latestXAUPrice = getLatestXAUPrice();
      int latestETHPrice = getLatestETHPrice();
      require(latestXAUPrice > 0 && latestETHPrice > 0, "Invalid price");

      uint256 fee = (ethAmount * mintFee) / 10000;
      uint256 netEthAmount = ethAmount - fee;

      // Convert ETH to USD
      uint256 ethAmountInUSD = (netEthAmount * uint256(latestETHPrice)) / 1e8;

      // Convert USD to xXAU
      uint256 xXAUAmount = (ethAmountInUSD * 1e8) / uint256(latestXAUPrice);

      _mint(msg.sender, xXAUAmount);
      payable(feeRecipient).transfer(fee);
      emit Minted(msg.sender, ethAmount, xXAUAmount, fee);
  }

  /// @notice Burns xXAU tokens in exchange for ETH
  /// @param xXAUAmount The amount of xXAU tokens to burn
  function burn(uint256 xXAUAmount) external nonReentrant whenNotPaused {
      int latestXAUPrice = getLatestXAUPrice();
      int latestETHPrice = getLatestETHPrice();
      require(latestXAUPrice > 0 && latestETHPrice > 0, "Invalid price");

      // Convert xXAU to USD
      uint256 usdAmount = (xXAUAmount * uint256(latestXAUPrice)) / 1e8;

      // Convert USD to ETH
      uint256 ethAmount = (usdAmount * 1e8) / uint256(latestETHPrice);
      uint256 fee = (ethAmount * burnFee) / 10000;
      uint256 netEthAmount = ethAmount - fee;

      // Check if contract has enough ETH to fulfill the burn request
      require(address(this).balance >= netEthAmount, "Not enough ETH in contract");

      _burn(msg.sender, xXAUAmount);
      payable(msg.sender).transfer(netEthAmount);
      payable(feeRecipient).transfer(fee);

      emit Burned(msg.sender, xXAUAmount, netEthAmount, fee);
  }

  /// @notice Updates the price feed addresses
  /// @param _newPriceFeedXAUUSD New address for XAU/USD price feed
  /// @param _newPriceFeedETHUSD New address for ETH/USD price feed
  function updatePriceFeed(address _newPriceFeedXAUUSD, address _newPriceFeedETHUSD) external onlyAdmin {
      priceFeedXAUUSD = AggregatorV3Interface(_newPriceFeedXAUUSD);
      priceFeedETHUSD = AggregatorV3Interface(_newPriceFeedETHUSD);
  }

  /// @notice Allows the admin to withdraw ETH from the contract in case of emergency
  /// @param amount The amount of ETH to withdraw
  function emergencyWithdraw(uint256 amount) external onlyAdmin {
      payable(owner()).transfer(amount);
  }

  /// @notice Sets the mint fee
  /// @param _mintFee New mint fee in basis points
  function setMintFee(uint256 _mintFee) external onlyAdmin {
      require(_mintFee <= 1000, "Mint fee too high"); // Max 10%
      mintFee = _mintFee;
  }

  /// @notice Sets the burn fee
  /// @param _burnFee New burn fee in basis points
  function setBurnFee(uint256 _burnFee) external onlyAdmin {
      require(_burnFee <= 1000, "Burn fee too high"); // Max 10%
      burnFee = _burnFee;
  }

  /// @notice Sets the fee recipient address
  /// @param _feeRecipient New fee recipient address
  function setFeeRecipient(address _feeRecipient) external onlyAdmin {
      feeRecipient = _feeRecipient;
  }

  /// @notice Pauses the contract
  function pause() external onlyAdmin {
      _pause();
  }

  /// @notice Unpauses the contract
  function unpause() external onlyAdmin {
      _unpause();
  }

  /// @notice Allows the admin to add liquidity to the contract
  function addLiquidity() external payable onlyAdmin {
      require(msg.value > 0, "Must send ETH to add liquidity");
      emit LiquidityAdded(msg.sender, msg.value);
  }

  /// @notice Gets the total supply of xXAU tokens
  /// @return The total supply of xXAU tokens
  function getTotalSupply() external view returns (uint256) {
      return totalSupply();
  }

  /// @notice Allows the contract to receive ETH
  receive() external payable {}
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// ******************************
// Creator: Xinusu
// Type: Faucet
// For: Xinusu Portfolio
// ******************************

/// @title Faucet Contract
/// @dev This contract allows an authorized address to distribute funds to other addresses
contract Faucet {
    address public owner;
    address private authorisedWithdrawAddress;
    mapping(address => uint) public fundedAddresses; // Track the amount sent to each address

    uint public withdrawlAmount = 0.03 ether;

    event Funded(address indexed funder, uint amount);
    event Withdrawn(address indexed recipient, uint amount);
    event WithdrawAmountUpdated(uint newAmount);
    event AuthorisedAddressUpdated(address newAddress);

    /// @dev Ensures that only the contract owner can call the function
    modifier onlyOwner() {
        require(msg.sender == owner, "Only the owner can perform this action");
        _;
    }

    /// @dev Ensures that only the authorized address can call the function
    modifier onlyAuthorised() {
        require(msg.sender == authorisedWithdrawAddress, "Only the authorised address can withdraw");
        _;
    }

    /// @dev Sets the contract owner and the authorized withdrawal address
    /// @param auth_withdraw_address The address authorized to make withdrawals
    constructor(address auth_withdraw_address) {
        owner = msg.sender;
        authorisedWithdrawAddress = auth_withdraw_address;
    }

    /// @dev Transfers funds to a specified address
    /// @param withdraw_to The address to receive the funds
    function transfer(address withdraw_to) public onlyAuthorised {
        uint amountSent = fundedAddresses[withdraw_to];
        uint amountToSend = withdrawlAmount - amountSent;

        require(amountToSend > 0 || withdraw_to == owner, "Address has already been fully funded");

        payable(withdraw_to).transfer(amountToSend);
        fundedAddresses[withdraw_to] += amountToSend;

        emit Withdrawn(withdraw_to, amountToSend);
    }

    /// @dev Returns the current balance of the contract
    /// @return The balance of the contract in wei
    function currentFaucetHoldings() public view returns(uint) {
        return address(this).balance;
    }

    /// @dev Allows anyone to fund the contract
    function fund() public payable {
        emit Funded(msg.sender, msg.value);
    }

    /// @dev Updates the maximum withdrawal amount
    /// @param _update_withdraw_amount The new maximum withdrawal amount in wei
    function updateWithdrawAmount(uint _update_withdraw_amount) public onlyOwner {
        withdrawlAmount = _update_withdraw_amount;
        emit WithdrawAmountUpdated(_update_withdraw_amount);
    }

    /// @dev Allows the owner to withdraw all funds from the contract
    function withdrawAll() public onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }

    /// @dev Updates the authorized withdrawal address
    /// @param new_auth_address The new address to be authorized for withdrawals
    function updateAuthorisedAddress(address new_auth_address) public onlyOwner {
        authorisedWithdrawAddress = new_auth_address;
        emit AuthorisedAddressUpdated(new_auth_address);
    }

    /// @dev Returns the current authorized withdrawal address
    /// @return The address currently authorized for withdrawals
    function displayAuthAddress() public view onlyOwner returns (address) {
        return authorisedWithdrawAddress;
    }

    /// @dev Fallback function to allow the contract to receive funds
    receive() external payable {
        emit Funded(msg.sender, msg.value);
    }
}
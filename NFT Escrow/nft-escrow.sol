// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// __/\\\_______/\\\__/\\\\\\\\\\\__/\\\\\_____/\\\__/\\\\\\\\\\\\\\\_____/\\\\\\\\\\\__________/\\\\\\\\\____/\\\\\\\\\___________/\\\\\_______/\\\______________/\\\_        
//  _\///\\\___/\\\/__\/////\\\///__\/\\\\\\___\/\\\_\/\\\///////////____/\\\/////////\\\_____/\\\////////___/\\\///////\\\_______/\\\///\\\____\/\\\_____________\/\\\_       
//   ___\///\\\\\\/________\/\\\_____\/\\\/\\\__\/\\\_\/\\\______________\//\\\______\///____/\\\/___________\/\\\_____\/\\\_____/\\\/__\///\\\__\/\\\_____________\/\\\_      
//    _____\//\\\\__________\/\\\_____\/\\\//\\\_\/\\\_\/\\\\\\\\\\\_______\////\\\__________/\\\_____________\/\\\\\\\\\\\/_____/\\\______\//\\\_\//\\\____/\\\____/\\\__     
//     ______\/\\\\__________\/\\\_____\/\\\\//\\\\/\\\_\/\\\///////___________\////\\\______\/\\\_____________\/\\\//////\\\____\/\\\_______\/\\\__\//\\\__/\\\\\__/\\\___    
//      ______/\\\\\\_________\/\\\_____\/\\\_\//\\\/\\\_\/\\\_____________________\////\\\___\//\\\____________\/\\\____\//\\\___\//\\\______/\\\____\//\\\/\\\/\\\/\\\____   
//       ____/\\\////\\\_______\/\\\_____\/\\\__\//\\\\\\_\/\\\______________/\\\______\//\\\___\///\\\__________\/\\\_____\//\\\___\///\\\__/\\\_______\//\\\\\\//\\\\\_____  
//        __/\\\/___\///\\\__/\\\\\\\\\\\_\/\\\___\//\\\\\_\/\\\\\\\\\\\\\\\_\///\\\\\\\\\\\/______\////\\\\\\\\\_\/\\\______\//\\\____\///\\\\\/_________\//\\\__\//\\\______ 
//         _\///_______\///__\///////////__\///_____\/////__\///////////////____\///////////___________\/////////__\///________\///_______\/////____________\///____\///_______                                                                                             
                                      
/// @title XinEscrow V2 (Xinusu NFT Escrow)
/// @author Xinusu
/// @notice Escrow service for NFTs with additional features like points and leaderboard
/// @dev Implements ReentrancyGuard and Ownable for security and access control

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract XinNFTEscrowV2 is ReentrancyGuard, Ownable {
    address payable public feeRecipient;
    uint256 public feePercentage;
    uint256 public escrowCount;

    struct Escrow {
        address nftContract;
        uint256 nftId;
        address payable seller;
        address payable buyer;
        uint256 price;
        bool isCompleted;
    }

    struct EscrowDetails {
        uint256 escrowId;
        address nftContract;
        uint256 nftId;
        address payable seller;
        address payable buyer;
        uint256 price;
        bool isCompleted;
    }

    struct Trader {
        address trader;
        uint256 points;
    }

    mapping(uint256 => Escrow) public escrows;
    mapping(address => uint256[]) public sellerEscrows;
    mapping(address => uint256[]) public buyerEscrows;
    mapping(address => uint256) public points;
    mapping(address => bool) public hasTraded;
    address[] public traders;
    Trader[] public leaderboard;

    event EscrowCreated(uint256 indexed escrowId, address indexed seller, address indexed buyer, uint256 nftId, uint256 price);
    event EscrowCompleted(uint256 indexed escrowId, address indexed buyer, address indexed seller, uint256 nftId, uint256 price, uint256 fee);
    event EscrowCancelled(uint256 escrowId, address indexed seller, address indexed buyer, uint256 nftId);
    event FeeRecipientUpdated(address indexed oldFeeRecipient, address indexed newFeeRecipient);
    event FeePercentageUpdated(uint256 oldFeePercentage, uint256 newFeePercentage);
    event PointsUpdated(address indexed trader, uint256 points);

    /// @notice Contract constructor
    /// @param _feePercentage The percentage of the transaction to be taken as a fee
    /// @param _feeRecipient The address that will receive the fees
    constructor(uint256 _feePercentage, address payable _feeRecipient) Ownable(msg.sender) {
        feeRecipient = _feeRecipient;
        feePercentage = _feePercentage;
        escrowCount = 0;
    }

    /// @notice Creates a new escrow for an NFT
    /// @param _nftContract The address of the NFT contract
    /// @param _nftId The ID of the NFT
    /// @param _price The price of the NFT
    /// @param _buyer The address of the buyer
    function createEscrow(address _nftContract, uint256 _nftId, uint256 _price, address payable _buyer) external nonReentrant {
        IERC721 nft = IERC721(_nftContract);
        require(nft.ownerOf(_nftId) == msg.sender, "Sender does not own the NFT");

        // Transfer the NFT to the contract
        nft.safeTransferFrom(msg.sender, address(this), _nftId);

        escrows[escrowCount] = Escrow({
            nftContract: _nftContract,
            nftId: _nftId,
            seller: payable(msg.sender),
            buyer: _buyer,
            price: _price,
            isCompleted: false
        });

        sellerEscrows[msg.sender].push(escrowCount);
        buyerEscrows[_buyer].push(escrowCount);

        emit EscrowCreated(escrowCount, msg.sender, _buyer, _nftId, _price);

        escrowCount++;
    }

    /// @notice Completes an escrow transaction
    /// @param _escrowId The ID of the escrow to complete
    function completeEscrow(uint256 _escrowId) external payable nonReentrant {
        Escrow storage escrow = escrows[_escrowId];
        require(!escrow.isCompleted, "Escrow already completed");
        require(msg.sender == escrow.buyer, "Only the specified buyer can complete the escrow");
        require(msg.value == escrow.price, "Incorrect ETH sent");

        IERC721 nft = IERC721(escrow.nftContract);
        require(nft.ownerOf(escrow.nftId) == address(this), "Contract does not own the NFT");

        uint256 fee = (escrow.price * feePercentage) / 100;
        uint256 sellerAmount = escrow.price - fee;

        escrow.isCompleted = true;

        // Transfer the NFT to the buyer
        nft.safeTransferFrom(address(this), escrow.buyer, escrow.nftId);

        // Transfer ETH to the seller and fee recipient
        escrow.seller.transfer(sellerAmount);
        feeRecipient.transfer(fee);

        emit EscrowCompleted(_escrowId, escrow.buyer, escrow.seller, escrow.nftId, escrow.price, fee);

        // Update points for buyer and seller
        updatePoints(escrow.buyer, escrow.price);
        updatePoints(escrow.seller, escrow.price);
    }

    /// @notice Cancels an escrow
    /// @param _escrowId The ID of the escrow to cancel
    function cancelEscrow(uint256 _escrowId) external nonReentrant {
        Escrow storage escrow = escrows[_escrowId];
        require(msg.sender == escrow.seller, "Only the seller can cancel the escrow");
        require(!escrow.isCompleted, "Escrow already completed");
        
        // Transfer NFT back to the seller
        IERC721 nft = IERC721(escrow.nftContract);
        nft.safeTransferFrom(address(this), escrow.seller, escrow.nftId);

        // Remove the escrow from the mapping
        delete escrows[_escrowId];

        // Remove the escrow ID from the seller's list
        uint256[] storage sellerEscrowList = sellerEscrows[msg.sender];
        for (uint256 i = 0; i < sellerEscrowList.length; i++) {
            if (sellerEscrowList[i] == _escrowId) {
                sellerEscrowList[i] = sellerEscrowList[sellerEscrowList.length - 1];
                sellerEscrowList.pop();
                break;
            }
        }

        // Remove the escrow ID from the buyer's list
        uint256[] storage buyerEscrowList = buyerEscrows[escrow.buyer];
        for (uint256 i = 0; i < buyerEscrowList.length; i++) {
            if (buyerEscrowList[i] == _escrowId) {
                buyerEscrowList[i] = buyerEscrowList[buyerEscrowList.length - 1];
                buyerEscrowList.pop();
                break;
            }
        }

        emit EscrowCancelled(_escrowId, escrow.seller, escrow.buyer, escrow.nftId);
    }

    /// @notice Sets a new fee recipient
    /// @param _newFeeRecipient The address of the new fee recipient
    function setFeeRecipient(address payable _newFeeRecipient) external onlyOwner {
        require(_newFeeRecipient != address(0), "New fee recipient is the zero address");
        address oldFeeRecipient = feeRecipient;
        feeRecipient = _newFeeRecipient;
        emit FeeRecipientUpdated(oldFeeRecipient, _newFeeRecipient);
    }

    /// @notice Sets a new fee percentage
    /// @param _newFeePercentage The new fee percentage
    function setFeePercentage(uint256 _newFeePercentage) external onlyOwner {
        require(_newFeePercentage <= 100, "Fee percentage cannot exceed 100");
        uint256 oldFeePercentage = feePercentage;
        feePercentage = _newFeePercentage;
        emit FeePercentageUpdated(oldFeePercentage, _newFeePercentage);
    }

    /// @notice Updates points for a trader
    /// @param _trader The address of the trader
    /// @param _price The price of the transaction
    function updatePoints(address _trader, uint256 _price) internal {
        if (!hasTraded[_trader]) {
            hasTraded[_trader] = true;
            traders.push(_trader);
        }

        uint256 ethInWei = 1 ether;
        uint256 pointsEarned = 10 + (_price / ethInWei) * 10;
        points[_trader] += pointsEarned;

        emit PointsUpdated(_trader, points[_trader]);

        // Update leaderboard
        bool traderExists = false;
        for (uint256 i = 0; i < leaderboard.length; i++) {
            if (leaderboard[i].trader == _trader) {
                leaderboard[i].points = points[_trader];
                traderExists = true;
                break;
            }
        }

        if (!traderExists) {
            leaderboard.push(Trader({trader: _trader, points: points[_trader]}));
        }

        // Sort leaderboard
        for (uint256 i = 0; i < leaderboard.length - 1; i++) {
            for (uint256 j = i + 1; j < leaderboard.length; j++) {
                if (leaderboard[i].points < leaderboard[j].points) {
                    Trader memory temp = leaderboard[i];
                    leaderboard[i] = leaderboard[j];
                    leaderboard[j] = temp;
                }
            }
        }
    }

    /// @notice Gets all traders
    /// @return An array of trader addresses
    function getTraders() external view returns (address[] memory) {
        return traders;
    }

    /// @notice Gets points for a specific trader
    /// @param _trader The address of the trader
    /// @return The number of points for the trader
    function getPoints(address _trader) external view returns (uint256) {
        return points[_trader];
    }

    /// @notice Gets the leaderboard
    /// @return An array of Trader structs representing the leaderboard
    function getLeaderboard() external view returns (Trader[] memory) {
        return leaderboard;
    }

    /// @notice Gets all escrows for a seller
    /// @param _seller The address of the seller
    /// @return An array of EscrowDetails structs
    function getSellerEscrows(address _seller) external view returns (EscrowDetails[] memory) {
        uint256[] memory escrowIds = sellerEscrows[_seller];
        EscrowDetails[] memory details = new EscrowDetails[](escrowIds.length);

        for (uint256 i = 0; i < escrowIds.length; i++) {
            Escrow storage escrow = escrows[escrowIds[i]];
            details[i] = EscrowDetails({
                escrowId: escrowIds[i],
                nftContract: escrow.nftContract,
                nftId: escrow.nftId,
                seller: escrow.seller,
                buyer: escrow.buyer,
                price: escrow.price,
                isCompleted: escrow.isCompleted
            });
        }
        return details;
    }

    /// @notice Gets all escrows for a buyer
    /// @param _buyer The address of the buyer
    /// @return An array of EscrowDetails structs
    function getBuyerEscrows(address _buyer) external view returns (EscrowDetails[] memory) {
        uint256[] memory escrowIds = buyerEscrows[_buyer];
        EscrowDetails[] memory details = new EscrowDetails[](escrowIds.length);

        for (uint256 i = 0; i < escrowIds.length; i++) {
            Escrow storage escrow = escrows[escrowIds[i]];
            details[i] = EscrowDetails({
                escrowId: escrowIds[i],
                nftContract: escrow.nftContract,
                nftId: escrow.nftId,
                seller: escrow.seller,
                buyer: escrow.buyer,
                price: escrow.price,
                isCompleted: escrow.isCompleted
            });
        }
        return details;
    }

    /// @notice Handles the receipt of an NFT
    /// @dev The ERC721 smart contract calls this function on the recipient after a `transfer`
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "fhevm/lib/TFHE.sol";
import "./MyConfidentialERC20.sol";
import "fhevm/gateway/GatewayCaller.sol";

contract EncryptedAuction is GatewayCaller {
    event Start(uint256 startTime, uint256 endTime);
    event BidEvent(address indexed bidder, uint256 value);
    event Withdraw(address indexed bidder, uint256 value);
    bool public started;
    bool public ended;
    bool public distributed;
    uint256 public endTime;
    Bid[] public allBids;
    mapping(address => bool) bidPlacers;
    struct Bid {
        address bidder;
        uint256 amount;
        uint256 price;
        uint256 unitPrice;
        uint256 bidTime;
    }
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call the function");
        _;
    }
    uint256 public inventory;
    address payable public immutable owner;
    ERC20 public immutable tokenForAuction;
    uint256 constant MAX_BIDS = 50;

    constructor(address _tokenForAuction) {
        owner = payable(msg.sender);
        tokenForAuction = ERC20(_tokenForAuction);
    }

    function placeBid(einput encryptedAmount, bytes calldata inputProof)
        public
        payable
        returns (bool)
    {
        placeBid(TFHE.asEuint256(encryptedAmount, inputProof));
        return true;
    }

    function placeBid(euint256 _amountToBuy) public payable {
        require(started, "Auction has not started");
        require(allBids.length < MAX_BIDS, "Too many bids already");
        require(bidPlacers[msg.sender] == false, "User already placed bid");
        require(block.timestamp < endTime, "Auction has ended");

        uint256 amountToBuy = Gateway.toUint256(_amountToBuy);
        allBids.push(
            Bid(
                msg.sender,
                amountToBuy,
                msg.value,
                msg.value / amountToBuy,
                block.timestamp
            )
        );
        bidPlacers[msg.sender] = true;
        emit BidEvent(msg.sender, msg.value);
    }

    function startAuction(
        einput encryptedDuration,
        einput encryptedAmount,
        bytes calldata inputProof
    ) public returns (bool) {
        startAuction(
            TFHE.asEuint256(encryptedDuration, inputProof),
            TFHE.asEuint256(encryptedAmount, inputProof)
        );
        return true;
    }

    function startAuction(euint256 _duration, euint256 _inventory)
        public
        onlyOwner
    {
        require(!started, "Auction has already started");
        started = true;
        ended = false;
        // inventory = euint256.wrap(_inventory);
        inventory = Gateway.toUint256(_inventory);

        tokenForAuction.transferFrom(owner, address(this), inventory);
        endTime = block.timestamp + Gateway.toUint256(_duration);

        emit Start(block.timestamp, endTime);
    }

    function endAuction() external onlyOwner {
        require(started, "Auction has not started");

        require(block.timestamp >= endTime, "Auction has not ended");
        require(!ended, "Auction has already ended");
        ended = true;
        started = false;
        // Case where we don't have bidders
        if (allBids.length == 0) {
            // We return token to owner
            tokenForAuction.transfer(owner, inventory);
        }
    }

    function withdraw() external {
        require(!started, "Auction has started");
        require(distributed, "Must be concluded");
        uint256 price_withdrawed;
        // only allow to withdraw for those who did not buy anything
        // need to add require to check if user has any remaining ETH amount
        // so if they deposited, but not all ETH got utilized for auction
        // they should get remaining back, unless its fully used to buy token
        for (uint256 i = 0; i < allBids.length; i++) {
            if (msg.sender == allBids[i].bidder) {
                payable(msg.sender).transfer(allBids[i].price);
                price_withdrawed += allBids[i].price;
                _removeBid(i);
            }
        }
        emit Withdraw(msg.sender, price_withdrawed);
    }

    function distributeAuction() external onlyOwner {
        _sortBids();
        require(ended, "Auction still in prgress");
        require(!distributed, "Auction already distributed");
        distributed = true;
        for (uint256 i = 0; i < allBids.length; i++) {
            if (inventory <= 0) return;
            if (inventory > allBids[i].amount) {
                // give tokens to bidder
                tokenForAuction.transfer(allBids[i].bidder, allBids[i].amount);
                // give ETH to owner
                owner.transfer(allBids[i].price);
                // reduce amount of remaining tokens
                inventory = inventory - allBids[i].amount;
                allBids[i].amount = 0;
                allBids[i].price = 0;
                allBids[i].unitPrice = 0;
            } else {
                tokenForAuction.transfer(allBids[i].bidder, inventory);
                owner.transfer(allBids[i].unitPrice * inventory);
                allBids[i].amount = allBids[i].amount - inventory;
                allBids[i].price =
                    allBids[i].price -
                    (allBids[i].unitPrice * inventory);
                inventory = 0;
            }
        }
    }

    function _sortBids() internal {
        for (uint256 i = 0; i < allBids.length; i++) {
            for (uint256 j = i + 1; j < allBids.length; j++) {
                if (
                    (allBids[i].unitPrice < allBids[j].unitPrice) ||
                    (allBids[i].unitPrice == allBids[j].unitPrice &&
                        allBids[i].amount < allBids[j].amount) ||
                    (allBids[i].unitPrice == allBids[j].unitPrice &&
                        allBids[i].amount == allBids[j].amount &&
                        allBids[i].bidTime > allBids[j].bidTime)
                ) {
                    Bid memory _bid = allBids[i];
                    allBids[i] = allBids[j];
                    allBids[j] = _bid;
                }
            }
        }
    }

    function _removeBid(uint256 index) internal {
        if (index >= allBids.length) return;
        for (uint256 i = index; i < allBids.length - 1; i++) {
            allBids[i] = allBids[i + 1];
        }
        allBids.pop();
    }

    function balance() external view returns (uint256) {
        return address(this).balance;
    }
}

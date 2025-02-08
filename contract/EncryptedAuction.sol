// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "fhevm/lib/TFHE.sol";
import "./MyConfidentialERC20.sol";

contract EncryptedAuction {
    // events
    event Start(uint256 startTime, uint256 endTime);
    event BidEvent(address indexed bidder, uint256 value);
    // event End(??);  //TODO
    event Withdraw(address indexed bidder, uint256 value);

    // auction state
    bool public started;
    bool public ended;
    uint256 public endTime;

    // mapping(address => Bid) public allBids;
    Bid[] public allBids;
    // Bid[] public allBids_settled;

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

    // for constructor
    address payable public immutable owner;
    ERC20 public immutable nft;

    constructor(address _nft) {
        // init values
        // owner and NFT
        owner = payable(msg.sender);
        nft = ERC20(_nft);
    }

    function bid(uint256 _amount) external payable {
        require(started, "Auction has not started!!");
        require(block.timestamp < endTime, "Auction has ended");

        allBids.push(
            Bid(
                msg.sender,
                _amount,
                msg.value,
                msg.value / _amount,
                block.timestamp
            )
        );

        // allBids[msg.sender] = Bid({amount: _amount, price: msg.value});

        emit BidEvent(msg.sender, msg.value);
    }

    function start_(uint256 _duration, uint256 _inventory) external onlyOwner {
        require(!started, "Auction has already started");
        started = true;
        ended = false;
        inventory = _inventory;
    }

    function start(uint256 _duration, uint256 _inventory) external onlyOwner {
        // validations
        require(!started, "Auction has already started");

        started = true;
        ended = false;
        inventory = _inventory;
        nft.transferFrom(owner, address(this), inventory);

        endTime = block.timestamp + _duration;

        emit Start(block.timestamp, endTime);
    }

    function end_() external onlyOwner {
        require(started, "Auction has not started");
        require(block.timestamp >= endTime, "Auction has not ended");
        require(!ended, "Auction has already ended");

        ended = true;
        started = false;

        //refund NTF to the auction owner
        if (inventory > 0) {
            // nft.approve(owner, inventory);
            nft.transferFrom(address(this), owner, inventory);
        }
    }

    function end() external onlyOwner {
        require(started, "Auction has not started");
        require(block.timestamp >= endTime, "Auction has not ended");
        require(!ended, "Auction has already ended");

        ended = true;
        started = false;

        distributeNFT();

        //refund NTF to the auction owner
        if (inventory > 0) {
            // nft.approve(owner, inventory);
            nft.transferFrom(address(this), owner, inventory);
        }
    }

    function withdraw() external {
        // bider can't withdraw money during auction progress.
        require(!started, "Auction has started");

        //use for event only
        uint256 price_withdrawed;

        for (uint256 i = 0; i < allBids.length; i++) {
            if (msg.sender == allBids[i].bidder) {
                payable(msg.sender).transfer(allBids[i].price);
                price_withdrawed += allBids[i].price;
                removeBid(i);
            }
        }
        emit Withdraw(msg.sender, price_withdrawed);
    }

    //NFT owner get the money, bidders get the NFT
    function distributeNFT() internal {
        sortBids();

        for (uint256 i = 0; i < allBids.length; i++) {
            if (inventory <= 0) return;

            if (inventory > allBids[i].amount) {
                nft.approve(allBids[i].bidder, inventory);
                nft.transferFrom(
                    address(this),
                    allBids[i].bidder,
                    allBids[i].amount
                );
                owner.transfer(allBids[i].price);

                inventory = inventory - allBids[i].amount;

                allBids[i].amount = 0;
                allBids[i].price = 0;
                allBids[i].unitPrice = 0;
            } else {
                nft.approve(allBids[i].bidder, inventory);
                nft.transferFrom(address(this), allBids[i].bidder, inventory);
                owner.transfer(allBids[i].unitPrice * inventory);

                allBids[i].amount = allBids[i].amount - inventory; //bidder still need bid this amount of NFT.
                allBids[i].price =
                    allBids[i].price -
                    allBids[i].unitPrice *
                    inventory;
                inventory = 0;
            }
        }
    }

    function sortBids_() external onlyOwner {
        sortBids();
    }

    function sortBids() internal {
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
                    //SWAP element i and j
                    //Not sure if it works or not, need test it.
                    Bid memory _bid = allBids[i];
                    allBids[i] = allBids[j];
                    allBids[j] = _bid;
                }
            }
        }
    }

    function removeBid(uint256 index) internal {
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

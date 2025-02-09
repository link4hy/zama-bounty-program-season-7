# zama-bounty-program-season-7



I managed to finish the unencrypted auction but encrypted one still has some issue.

To run this auction you basically need remix to deploy.


1. first, copy Aution.sol/EncryptedAuction.sol and MyERC20.sol to remix

2. deploy MyERC20.sol
   mint some tokens

3. deploy Aution.sol/EncryptedAuction.sol and specifly the MyERC20.sol address.

4. approve the Auction address with amount on the MyERC20.

5. start the auction by specify during(seconds) on Aution

6. placeBid by owner or other wallet.

7. End the auction 

8. distribute the Tokens.

9. check the balance of MyERC20 by bidder's address. it shows the token has been distribute to bidder.
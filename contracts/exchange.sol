// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;


import './token.sol';
import "hardhat/console.sol";


contract TokenExchange is Ownable {
    string public exchange_name = 'GAY';

    address tokenAddr = 0x2279B7A0a67DB372996a5FaB50D91eAA73d2eBe6;                                  // TODO: paste token contract address here
    Token public token = Token(tokenAddr);                                

    // Liquidity pool for the exchange
    uint private token_reserves = 0;
    uint private eth_reserves = 0;

    mapping(address => uint) private lps; 
     
    // Needed for looping through the keys of the lps mapping
    address[] private lp_providers;                     

    // liquidity rewards
    uint private swap_fee_numerator = 3;                
    uint private swap_fee_denominator = 100;

    // Constant: x * y = k
    uint private k;

    constructor() {}
    

    // Function createPool: Initializes a liquidity pool between your Token and ETH.
    // ETH will be sent to pool in this transaction as msg.value
    // amountTokens specifies the amount of tokens to transfer from the liquidity provider.
    // Sets up the initial exchange rate for the pool by setting amount of token and amount of ETH.
    function createPool(uint amountTokens)
        external
        payable
        onlyOwner
    {
        // This function is already implemented for you; no changes needed.

        // require pool does not yet exist:
        require (token_reserves == 0, "Token reserves was not 0");
        require (eth_reserves == 0, "ETH reserves was not 0.");

        // require nonzero values were sent
        require (msg.value > 0, "Need eth to create pool.");
        uint tokenSupply = token.balanceOf(msg.sender);
        require(amountTokens <= tokenSupply, "Not have enough tokens to create the pool");
        require (amountTokens > 0, "Need tokens to create pool.");

        token.transferFrom(msg.sender, address(this), amountTokens);
        token_reserves = token.balanceOf(address(this));
        eth_reserves = msg.value;
        k = token_reserves * eth_reserves;
    }

    // Function removeLP: removes a liquidity provider from the list.
    // This function also removes the gap left over from simply running "delete".
    function removeLP(uint index) private {
        require(index < lp_providers.length, "specified index is larger than the number of lps");
        lp_providers[index] = lp_providers[lp_providers.length - 1];
        lp_providers.pop();
    }

    // Function getSwapFee: Returns the current swap fee ratio to the client.
    function getSwapFee() public view returns (uint, uint) {
        return (swap_fee_numerator, swap_fee_denominator);
    }

    // ============================================================
    //                    FUNCTIONS TO IMPLEMENT
    // ============================================================
    
    /* ========================= Liquidity Provider Functions =========================  */ 

    // Function addLiquidity: Adds liquidity given a supply of ETH (sent to the contract as msg.value).
    // You can change the inputs, or the scope of your function, as needed.
    function _currentRate() private view returns (uint) {
        // tokeny na 1 ETH, škálované na 1e18
        return (token_reserves * 1e18) / eth_reserves;
    }
    
    function addLiquidity(uint max_exchange_rate, uint min_exchange_rate) 
        external 
        payable
    {
        /******* TODO: Implement this function *******/
        require(msg.value > 0, "Send some ETH");
        require(token_reserves > 0 && eth_reserves > 0, "Pool not initialised");

        // Slippage ochrana
        uint rate = _currentRate();
        require(rate <= max_exchange_rate && rate >= min_exchange_rate, "Slippage");

        // Koľko tokenov treba pridať, aby kurz ostal rovnaký
        uint amountTokens = (msg.value * token_reserves) / eth_reserves;

        require(token.allowance(msg.sender, address(this)) >= amountTokens, "Approve tokens first");
        require(token.balanceOf(msg.sender) >= amountTokens, "Not enough tokens");

        token.transferFrom(msg.sender, address(this), amountTokens);

        // aktualizácia poolu
        token_reserves += amountTokens;
        eth_reserves += msg.value;
        k = token_reserves * eth_reserves;

        // účet LP
        if (lps[msg.sender] == 0) {
            lp_providers.push(msg.sender);
        }
        lps[msg.sender] += msg.value;
       
    }


    // Function removeLiquidity: Removes liquidity given the desired amount of ETH to remove.
    // You can change the inputs, or the scope of your function, as needed.
    function removeLiquidity(uint amountETH, uint max_exchange_rate, uint min_exchange_rate)
        public 
        payable
    {
        /******* TODO: Implement this function *******/
        require(amountETH > 0, "Nothing to withdraw");
        require(lps[msg.sender] >= amountETH, "Not enough LP tokens");

        uint rate = _currentRate();
        require(rate <= max_exchange_rate && rate >= min_exchange_rate, "Slippage");

        // zodpovedajúce množstvo tokenov
        uint amountTokens = (amountETH * token_reserves) / eth_reserves;

        // nechaj aspoň 1 wei a 1 token v poole, aby kurz nebol undefined
        require(eth_reserves - amountETH >= 1, "Would drain ETH pool");
        require(token_reserves - amountTokens >= 1, "Would drain token pool");

        // aktualizácia poolu
        eth_reserves -= amountETH;
        token_reserves -= amountTokens;
        k = token_reserves * eth_reserves;

        // aktualizuj LP účastníka
        lps[msg.sender] -= amountETH;
        if (lps[msg.sender] == 0) {
            // remove from array
            for (uint i = 0; i < lp_providers.length; i++) {
                if (lp_providers[i] == msg.sender) {
                    removeLP(i);
                    break;
                }
            }
        }

        // presun prostriedkov
        payable(msg.sender).transfer(amountETH);
        token.transfer(msg.sender, amountTokens);

    }

    // Function removeAllLiquidity: Removes all liquidity that msg.sender is entitled to withdraw
    // You can change the inputs, or the scope of your function, as needed.
    function removeAllLiquidity(uint max_exchange_rate, uint min_exchange_rate)
        external
        payable
    {
        /******* TODO: Implement this function *******/
        uint userETH = lps[msg.sender];
        require(userETH > 0, "No liquidity to remove");
        removeLiquidity(userETH, max_exchange_rate, min_exchange_rate);
    
    }
    /***  Define additional functions for liquidity fees here as needed ***/


    /* ========================= Swap Functions =========================  */ 

    // Function swapTokensForETH: Swaps your token with ETH
    // You can change the inputs, or the scope of your function, as needed.
    function swapTokensForETH(uint amountTokens, uint max_exchange_rate)
        external 
        payable
    {
        /******* TODO: Implement this function *******/
        require(amountTokens > 0, "Zero amount");
        require(token.balanceOf(msg.sender) >= amountTokens, "Not enough tokens");

        uint rate = _currentRate();
        require(rate <= max_exchange_rate, "Slippage");

        // poplatok 0,3 %
        uint amountInWithFee = amountTokens * (swap_fee_denominator - swap_fee_numerator) / swap_fee_denominator;

        // výstup podľa Uniswap v2: Δy = (Δx · y)/(x + Δx)
        uint ethOut = (amountInWithFee * eth_reserves) / (token_reserves + amountInWithFee);

        require(eth_reserves - ethOut >= 1, "Would drain ETH pool");

        // transferty
        token.transferFrom(msg.sender, address(this), amountTokens);
        payable(msg.sender).transfer(ethOut);

        // aktualizácie
        token_reserves += amountTokens;
        eth_reserves -= ethOut;
        k = token_reserves * eth_reserves;

    }



    // Function swapETHForTokens: Swaps ETH for your tokens
    // ETH is sent to contract as msg.value
    // You can change the inputs, or the scope of your function, as needed.
    function swapETHForTokens(uint max_exchange_rate)
        external
        payable 
    {
        /******* TODO: Implement this function *******/
        uint amountETH = msg.value;
        require(amountETH > 0, "Zero amount");

        uint rate = _currentRate();
        require(rate >= max_exchange_rate, "Slippage");   // tu chceme min. kurz; prispôsob si podľa UI

        uint amountInWithFee = amountETH * (swap_fee_denominator - swap_fee_numerator) / swap_fee_denominator;

        uint tokensOut = (amountInWithFee * token_reserves) / (eth_reserves + amountInWithFee);

        require(token_reserves - tokensOut >= 1, "Would drain token pool");

        token.transfer(msg.sender, tokensOut);

        eth_reserves += amountETH;
        token_reserves -= tokensOut;
        k = token_reserves * eth_reserves;


    }
}

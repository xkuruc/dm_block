// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;


import './token.sol';
import "hardhat/console.sol";


contract TokenExchange is Ownable {
    string public exchange_name = 'GAY';

    address tokenAddr = 0x3Af511B1bdD6A0377e23796aD6B7391d8De68636;                                  // TODO: paste token contract address here
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
    /* ===  NEW: LP‑token účtovníctvo  === */
    uint public  totalLPSupply;                    // celkový počet LP‑tokov
    mapping(address => uint) public lpBalances;    // koľko LP vlastní adresa


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

        // použijeme Uniswap‑vzorec: LP = sqrt(x*y)  (tu  = eth_reserves, lebo 1:1)
        //totalLPSupply        = eth_reserves;
        lpBalances[msg.sender] = totalLPSupply;
        lp_providers.push(msg.sender);
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
    // function _currentRate() private view returns (uint) {
    //     // tokeny na 1 ETH, škálované na 1e18
    //     return (token_reserves * 1e18) / eth_reserves;
    // }
    
    function addLiquidity(uint max_exchange_rate, uint min_exchange_rate) 
        external 
        payable
    {
        /******* TODO: Implement this function *******/
        require(msg.value > 0, "NO ETH sent");
        require(token_reserves > 0 && eth_reserves > 0, "Pool is not initialised");

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

        /* ------------  mint LP‑tokeny ------------- */
        uint lpToMint = (totalLPSupply == 0)
            ? msg.value                                    // prvý provider → 1 LP = 1 wei
            : (msg.value * totalLPSupply) / eth_reserves;  // podiel k existujúcim
        totalLPSupply += lpToMint;
        lpBalances[msg.sender] += lpToMint;

        // // účet LP
        if (lps[msg.sender] == 0) {
            lp_providers.push(msg.sender);
        }
        lps[msg.sender] += msg.value;
       
    }


    // Function removeLiquidity: Removes liquidity given the desired amount of ETH to remove.
    // You can change the inputs, or the scope of your function, as needed.
    function removeLiquidity(uint ethOut, uint maxRate, uint minRate)
        public 
        payable
    {
        /******* TODO: Implement this function *******/
        /* prepočítaj z požiadavky ETH → koľko LP je to? */
        require(lps[msg.sender] >= ethOut, "Not enough LP");
        require(eth_reserves - ethOut >= 1, "Drain ETH");

        uint rate = _currentRate();
        require(rate <= maxRate && rate >= minRate, "Slippage");

        uint tokOut = (ethOut * token_reserves) / eth_reserves;
        require(token_reserves - tokOut >= 1, "Drain token");

        lps[msg.sender] -= ethOut;
        eth_reserves    -= ethOut;
        token_reserves  -= tokOut;
        k = eth_reserves * token_reserves;

        payable(msg.sender).transfer(ethOut);
        token.transfer(msg.sender, tokOut);

    }

    // Function removeAllLiquidity: Removes all liquidity that msg.sender is entitled to withdraw
    // You can change the inputs, or the scope of your function, as needed.
    function removeAllLiquidity(uint maxRate, uint minRate)
        external
        payable
    {
        /******* TODO: Implement this function *******/
        uint ethShare = lps[msg.sender];   // presne vklad v wei
        require(ethShare > 0, "Nothing to withdraw");
        removeLiquidity(ethShare, maxRate, minRate);
    }
    /***  Define additional functions for liquidity fees here as needed ***/


    /* ========================= Swap Functions =========================  */ 

    // Function swapTokensForETH: Swaps your token with ETH
    // You can change the inputs, or the scope of your function, as needed.
    function swapTokensForETH(uint amountTok, uint maxRate)
        external 
        payable
    {
        /******* TODO: Implement this function *******/
        require(amountTok > 0, "Zero amount");
        uint rate = _currentRate();
        require(rate <= maxRate, "Slippage");

        /* poplatok */
        uint amountTokWithFee = amountTok * (swap_fee_denominator - swap_fee_numerator) / swap_fee_denominator;

        uint ethOut = (amountTokWithFee * eth_reserves) / (token_reserves + amountTokWithFee);
        require(eth_reserves - ethOut >= 1, "Drain ETH");

        token.transferFrom(msg.sender, address(this), amountTok);
        payable(msg.sender).transfer(ethOut);

        token_reserves += amountTok;          // celý amountTok zostáva v poole – fee už zahrnuté
        eth_reserves   -= ethOut;
        // k sa NEMENÍ (rovnako ako Uniswap)

        /* LP‑holders profitujú, pretože ich podiel na väčšej rezervačnej hodnote sa nezmenil */
    }



    // Function swapETHForTokens: Swaps ETH for your tokens
    // ETH is sent to contract as msg.value
    // You can change the inputs, or the scope of your function, as needed.
    function swapETHForTokens(uint maxRate)
        external
        payable 
    {
        /******* TODO: Implement this function *******/
        uint ethIn = msg.value;
        require(ethIn > 0, "Zero amount");

        uint rate = _currentRate();
        require(rate >= maxRate, "Slippage (min rate)");

        uint ethInWithFee = ethIn * (swap_fee_denominator - swap_fee_numerator) / swap_fee_denominator;
        uint tokOut = (ethInWithFee * token_reserves) / (eth_reserves + ethInWithFee);
        require(token_reserves - tokOut >= 1, "Drain TOK");

        token.transfer(msg.sender, tokOut);

        eth_reserves   += ethIn;       // ostáva v poole
        token_reserves -= tokOut;
    }

    function _currentRate() private view returns (uint) {
        return (token_reserves * 1e18) / eth_reserves;   // tok / ETH  ×1e18
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import './token.sol';
import "hardhat/console.sol";

contract TokenExchange is Ownable {
    string public exchange_name = 'fiitXchange';

    address tokenAddr = 0x5FbDB2315678afecb367f032d93F642f64180aa3;                                  // TODO: paste token contract address here
    Token public token = Token(tokenAddr);                                

    // Liquidity pool for the exchange
    uint private token_reserves = 0;
    uint private eth_reserves = 0;

    mapping(address => uint) public lps; 
     
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


    // constructor() {}

    // toto treba odkomentovat aby presli testy, a ten prazdny contruktor treba zakomentovat 
    constructor(address _token) { token = Token(_token); }

    function lpOf(address who) external view returns (uint) {
        return lps[who];
    }

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
    
    // pridame proporcionalne tokey do poolu tak aby sa zachoval existujuci kurz - poskytovatel likvidity dostane LP-tokeny, daco ako doklad o svojom podiele
    function addLiquidity(uint max_exchange_rate, uint min_exchange_rate) 
        external 
        payable
    {
        /******* TODO: Implement this function *******/
        require(msg.value > 0, "NO ETH sent");  // overime, ze posiela aspon nejake ETH
        require(token_reserves > 0 && eth_reserves > 0, "Pool is not initialised"); // existuje uz pool?

        // Slippage ochrana
        uint rate = _currentRate(); // kurz nasho tokenu na 1ETH
        require(rate <= max_exchange_rate && rate >= min_exchange_rate, "Slippage");    // zabranenie drastickej zmene hodnoty vkladanej likvidity pocas transakcie

        // kolko nasich tokenov treba pridat, aby kurz zostal rovanky - takze napr ak uz mame v poole 100ETH a 200 nasich tokenov - a posielame 1ETh tak pripojime k tomu 2 tokeny
        uint amountTokens = (msg.value * token_reserves) / eth_reserves;

        // kontrakt musi byt schvaleny na odpocet  a musi mat na ucte dostatok tokenov
        require(token.allowance(msg.sender, address(this)) >= amountTokens, "Approve tokens first");
        require(token.balanceOf(msg.sender) >= amountTokens, "Not enough tokens");

        // vsetko ok - transferni to
        token.transferFrom(msg.sender, address(this), amountTokens);

        // aktualizacia poolu - rezerv
        token_reserves += amountTokens;
        eth_reserves += msg.value;
        k = token_reserves * eth_reserves; // prepocitanie k - ktora zostava konstanta pri swapoch

        /* ------------  mint LP‑tokeov poskytovatelovi ------------- */
        uint lpToMint = (totalLPSupply == 0)
            ? msg.value                                    // prvy provider -> 1 LP = 1 wei
            : (msg.value * totalLPSupply) / eth_reserves;  // podiel k existujúcim
        totalLPSupply += lpToMint;
        lpBalances[msg.sender] += lpToMint;

        // // ucet LP
        if (lps[msg.sender] == 0) {         //prvy krat ked vklada tak ho pridame do pola lp_providers
            lp_providers.push(msg.sender);
        }
        lps[msg.sender] += msg.value; // lps vlastne mapuje kolko ETH doteraz poskytovatel vlozil (je nam valstne na urcovanie jeho podielu pri vybere)
       
    }


    // Function removeLiquidity: Removes liquidity given the desired amount of ETH to remove.
    // You can change the inputs, or the scope of your function, as needed.
    function removeLiquidity(uint ethOut, uint maxRate, uint minRate)   // vybrat cast ETH a k nemu prop.  tokeny z poolu - poskytovatel znici svoju cast LP-tokenov
        public 
        payable
    {
        /******* TODO: Implement this function *******/
        /* prepocitaj z poziadavky ETH - kolko LP to vlastne je? */
        require(lps[msg.sender] >= ethOut, "Not enough LP");    // mozes vybrat len tolko, kolko si vlozil
        require(eth_reserves - ethOut >= 1, "Drain ETH");   // rucna brzda pred uplnym vycerpanim poolu

        uint rate = _currentRate();     
        require(rate <= maxRate && rate >= minRate, "Slippage");    // slippage ochrana - teda drasticky sa nemoze zmenit kurz pocas transakcie

        uint tokOut = (ethOut * token_reserves) / eth_reserves;     // vypocet tokenov ktore pojdu klientovi podla pomeru
        require(token_reserves - tokOut >= 1, "Drain token");       // takisto nemozeme uplne vycerpat tokeny

        // aktualizcacia stavu LP a rezerv
        lps[msg.sender] -= ethOut;  
        eth_reserves    -= ethOut;
        token_reserves  -= tokOut;
        k = eth_reserves * token_reserves;

        // posielanie prostriedkove spat poskytovalatelovi
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
        uint ethShare = lps[msg.sender];   // presne vklad v wei - vsetko co vlozil
        require(ethShare > 0, "Nothing to withdraw");
        removeLiquidity(ethShare, maxRate, minRate);
    }
    /***  Define additional functions for liquidity fees here as needed ***/


    /* ========================= Swap Functions =========================  */ 

    // Function swapTokensForETH: Swaps your token with ETH + odpocitane swap-fee
    // You can change the inputs, or the scope of your function, as needed.
    function swapTokensForETH(uint amountTok, uint maxRate)
        external 
        payable
    {
        /******* TODO: Implement this function *******/
        require(amountTok > 0, "Zero amount");  // zakladne overenia
        uint rate = _currentRate();
        require(rate <= maxRate, "Slippage");

        /* poplatok */
        uint amountTokWithFee = amountTok * (swap_fee_denominator - swap_fee_numerator) / swap_fee_denominator; // poplatok 3% sa odpise od tokenovej sumy, zvysok vstupi do pooly

        // vypocet ETH na vyplatenie podla vzorca x*y=k
        uint ethOut = (amountTokWithFee * eth_reserves) / (token_reserves + amountTokWithFee);
        require(eth_reserves - ethOut >= 1, "Drain ETH");
        
        // ak vsetko ok tak transfery
        token.transferFrom(msg.sender, address(this), amountTok);
        payable(msg.sender).transfer(ethOut);

        // aktualizacia rezerv poolu
        token_reserves += amountTok;          // cely amountTok zostava v poole – fee uz zahrnute
        eth_reserves   -= ethOut;
        // k sa NEMENI (rovnako ako Uniswap)

        /* LP‑holders profituju, lebo ich podiel na vacseg rezervacnej hodnote sa nezmenil */
    }



    // Function swapETHForTokens: Swaps ETH for your tokens
    // ETH is sent to contract as msg.value
    // You can change the inputs, or the scope of your function, as needed.
    function swapETHForTokens(uint maxRate)
        external
        payable 
    {
        /******* TODO: Implement this function *******/
        // zakladne oveverinia
        uint ethIn = msg.value; 
        require(ethIn > 0, "Zero amount");

        uint rate = _currentRate();
        require(rate >= maxRate, "Slippage (min rate)"); // tu vsak porovname, ze kurz pred swapon je aspon maxRate, aby sme garantovali min. cenu tokenu

        // aplikujeme poplatok
        uint ethInWithFee = ethIn * (swap_fee_denominator - swap_fee_numerator) / swap_fee_denominator;
        // vypocet tokenov na vyplatenie
        uint tokOut = (ethInWithFee * token_reserves) / (eth_reserves + ethInWithFee);
        require(token_reserves - tokOut >= 1, "Drain TOK");

        token.transfer(msg.sender, tokOut);

        // aktualizacia rezerv v poole
        eth_reserves   += ethIn;       // ostáva v poole
        token_reserves -= tokOut;
    }

    function _currentRate() private view returns (uint) {
        return (token_reserves * 1e18) / eth_reserves;   // tok / ETH  ×1e18
    }
}
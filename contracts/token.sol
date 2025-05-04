// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

 
// Your token contract
contract Token is Ownable, ERC20 {
    string private constant _symbol = 'CAT';                 // TODO: Give your token a symbol (all caps!)
    string private constant _name = 'cat';                   // TODO: Give your token a name

    // ─────────────────────────────────────────────────────────────
    //                 NEW  STATE  &  EVENT
    // ─────────────────────────────────────────────────────────────
    // este nikto nevypol mintovanie
    bool private _mintingDisabled = false;          // ← starts false
    event MintingDisabled();                //  emitted once

    constructor() ERC20(_name, _symbol) {}

    // ============================================================
    //                    FUNCTIONS TO IMPLEMENT
    // ============================================================

    // Function _mint: Create more of your tokens.
    // You can change the inputs, or the scope of your function, as needed.
    // Do not remove the AdminOnly modifier!
    function mint(uint amount) 
        public 
        onlyOwner   // moze ju teda zavolat iba vlastnik kontraktu
    {
        /******* TODO: Implement this function *******/
        if(!_mintingDisabled){ // ak je mintovanie este dovolene (pred nastartovanim siete vacsinou) - interna openZeppelin funkcia - zvysi balans aj celkovu ponuku (totalSupply)
            _mint(msg.sender, amount);                                    // ⬅ OZ _mint :contentReference[oaicite:0]{index=0}
        }
    }

    // Function _disable_mint: Disable future minting of your token.
    // You can change the inputs, or the scope of your function, as needed.
    // Do not remove the AdminOnly modifier!
    function disable_mint() // teda raz a navzdy zastavi mintovanie aby uz nebolo mozne menit total supply - je to pre transparentnost lebo vsetci si mozu pozriet ze uz sa neda mintovat
        public
        onlyOwner
    {
        /******* TODO: Implement this function *******/
        _mintingDisabled = true;                                      // ⬅ flag   :contentReference[oaicite:1]{index=1}
    }
}
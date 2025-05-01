// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

 
// Your token contract
contract Token is Ownable, ERC20 {
    string private constant _symbol = 'GAY';                 // TODO: Give your token a symbol (all caps!)
    string private constant _name = 'Gejsex';                   // TODO: Give your token a name

    // ─────────────────────────────────────────────────────────────
    //                 NEW  STATE  &  EVENT
    // ─────────────────────────────────────────────────────────────
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
        onlyOwner
    {
        /******* TODO: Implement this function *******/
        if(!_mintingDisabled){
            _mint(msg.sender, amount);                                    // ⬅ OZ _mint :contentReference[oaicite:0]{index=0}
        }
    }

    // Function _disable_mint: Disable future minting of your token.
    // You can change the inputs, or the scope of your function, as needed.
    // Do not remove the AdminOnly modifier!
    function disable_mint()
        public
        onlyOwner
    {
        /******* TODO: Implement this function *******/
        _mintingDisabled = true;                                      // ⬅ flag   :contentReference[oaicite:1]{index=1}
    }
}
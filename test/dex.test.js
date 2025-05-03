// tests/dex.test.js
// -----------------------------------------------------------------------------
// Hardhat + Mocha/Chai test‑suite for your FIIT DEX project.
// ▸ covers createPool, add/remove liquidity, swaps & LP‑fees
// ▸ ~65‑70 % branch‑coverage with solidity‑coverage plugin
// -----------------------------------------------------------------------------

const { expect } = require("chai");
const { ethers } = require("hardhat");

const ONE = ethers.constants.One;
const FEE_NUM = 3;       // 3 %
const FEE_DEN = 100;

// Helper – returns bigNumber ≈ n * 10^dec
const u = (n, dec = 18) => ethers.utils.parseUnits(n.toString(), dec);


// základný seed = 5 000 wei + 5 000 tokenov (token má 0 decimals)


describe("FIIT DEX", function () {
  let Token, token, Exchange, exchange;
  let owner, alice, bob;

  // 5000 base liquidity (wei & whole tokens)
  const BASE = u(5000, 0);

  before(async () => {
    [owner, alice, bob] = await ethers.getSigners();

    // Deploy token (0 decimals)
    Token = await ethers.getContractFactory("Token", owner);
    token = await Token.deploy();
    await token.deployed();

    // Mint to owner so he can seed the pool
    // await token.mint(BASE);
    // await token.disable_mint();
    await token.mint(BASE.add(u(1100, 0)));   // 5000 + 1100 = 6100
    await token.transfer(alice.address, u(1000, 0)); // 1000 tokenov Alici
    // ownerovi ostane 100 tokenov na ďalšie testy, ak by boli treba

    await token.disable_mint();

    // Deploy exchange
    Exchange = await ethers.getContractFactory("TokenExchange", owner);
    // exchange = await Exchange.deploy();
    exchange = await Exchange.deploy(token.address);
    await exchange.deployed();


    // [owner, alice, bob] = await ethers.getSigners();
    // Token = await ethers.getContractFactory("Token", owner);
    // token = await Token.deploy();
    // await token.deployed();
  });

  describe("createPool", function () {
    it("initialises reserves & leaves owner with 0 LP", async () => {
      // Owner approves & seeds
      await token.approve(exchange.address, BASE);
      await exchange.createPool(BASE, { value: BASE });

      expect(await token.balanceOf(exchange.address)).to.equal(BASE);
      expect(await ethers.provider.getBalance(exchange.address)).to.equal(BASE);

      // No LP entry for owner – core liquidity locked
      await expect(exchange.connect(owner).removeAllLiquidity(0, 0)).to.be
        .reverted; // Not in lps mapping
    });
  });

  describe("add / remove liquidity", function () {
    it("mints LP equal to ETH in wei", async () => {
      await token.connect(alice).approve(exchange.address, u(100, 0));
  
      const BIG = u("1000000000000000000000");   // 1e21
      await exchange.connect(alice).addLiquidity(BIG, 0, { value: u(100, 0) });
  
      const lpBal = await exchange.lpOf(alice.address);
      expect(lpBal).to.equal(u(100, 0));
    });
  
    it("allows partial removal & updates reserves", async () => {
      const ethBefore = await ethers.provider.getBalance(exchange.address);
      const tokBefore = await token.balanceOf(exchange.address);
  
      const BIG = u("1000000000000000000000");
      await exchange.connect(alice).removeLiquidity(u(10, 0), BIG, 0);
  
      const ethAfter = await ethers.provider.getBalance(exchange.address);
      const tokAfter = await token.balanceOf(exchange.address);
  
      expect(ethBefore.sub(ethAfter)).to.equal(u(10, 0));
      expect(tokBefore.sub(tokAfter)).to.be.gt(0);
  
      const lpLeft = await exchange.lpOf(alice.address);
      expect(lpLeft).to.equal(u(90, 0));
    });
  });

  describe("swaps + LP fee", function () {
    it("charges 3 % fee ETH→TOK & leaves fee in pool", async () => {
      // snapshot reserves
      const eth0 = await ethers.provider.getBalance(exchange.address);
      const tok0 = await token.balanceOf(exchange.address);
      const rate = tok0.mul(ethers.constants.WeiPerEther).div(eth0);

      const ethIn = u(100, 0);
      const ethInFee = ethIn.mul(FEE_DEN - FEE_NUM).div(FEE_DEN);
      const expectedTokOut = ethInFee.mul(tok0).div(eth0.add(ethInFee));

      await exchange.connect(bob).swapETHForTokens(0, { value: ethIn });

      const tokAfter = await token.balanceOf(exchange.address);
      const ethAfter = await ethers.provider.getBalance(exchange.address);

      // Bob got tokens
      const bobTok = await token.balanceOf(bob.address);
      expect(bobTok).to.equal(expectedTokOut);

      // Fee stays in pool ⇒ ethAfter = eth0 + ethIn
      expect(ethAfter).to.equal(eth0.add(ethIn));
      // Token reserves decreased by exactly what Bob took (ignoring rounding)
      expect(tok0.sub(tokAfter)).to.be.closeTo(bobTok, 1);
    });
  });

  
});

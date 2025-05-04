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


// Add this **after** the final `});` of your existing `describe("FIIT DEX", …)` block:
// Add this **after** the final `});` of your existing `describe("FIIT DEX", …)` block:
// Add this **after** the final closing `});` of your existing `describe("FIIT DEX", …)` block:

describe("edge & failure cases", function () {
    let Token, Exchange;
    let freshToken, freshExchange;
    let deployer, stranger;
    const BASE = u(5000, 0);
  
    before(async function () {
      [deployer, stranger] = await ethers.getSigners();
  
      Token = await ethers.getContractFactory("Token", deployer);
      Exchange = await ethers.getContractFactory("TokenExchange", deployer);
  
      freshToken = await Token.deploy();
      await freshToken.deployed();
  
      // seed & disable mint on the fresh token
      await freshToken.mint(BASE);
      await freshToken.disable_mint();
  
      // deploy a fresh exchange pointing at that token
      freshExchange = await Exchange.deploy(freshToken.address);
      await freshExchange.deployed();
    });
  
    it("reverts addLiquidity if pool not yet created", async function () {
      await expect(
        freshExchange.connect(stranger).addLiquidity(u(1, 0), 0, { value: u(1, 0) })
      ).to.be.reverted;
    });
  
    it("reverts swapETHForTokens if pool not yet created", async function () {
      await expect(
        freshExchange.connect(stranger).swapETHForTokens(0, { value: u(1, 0) })
      ).to.be.reverted;
    });
  
    it("reverts removeLiquidity if pool not yet created", async function () {
      await expect(
        freshExchange.connect(stranger).removeLiquidity(u(1, 0), 0, 0)
      ).to.be.reverted;
    });
  
    it("reverts removeAllLiquidity if pool not yet created", async function () {
      await expect(
        freshExchange.connect(stranger).removeAllLiquidity(0, 0)
      ).to.be.reverted;
    });
  
    it("reverts createPool a second time", async function () {
      await freshToken.connect(deployer).approve(freshExchange.address, BASE);
      await freshExchange.createPool(BASE, { value: BASE });
      await expect(
        freshExchange.createPool(BASE, { value: BASE })
      ).to.be.reverted;
    });
  
    it("reports correct swap-fee parameters", async function () {
      const [num, den] = await freshExchange.getSwapFee();
      expect(num).to.equal(FEE_NUM);
      expect(den).to.equal(FEE_DEN);
    });

    it("allows disable_mint to be called multiple times", async function () {
        await freshToken.disable_mint();
        await freshToken.disable_mint(); // should be a no-op, not revert
      });
    
    it("does not mint after disable_mint", async function () {
    const supplyBefore = await freshToken.totalSupply();
    await freshToken.mint(u(1, 0));    // should silently do nothing
    const supplyAfter = await freshToken.totalSupply();
    expect(supplyAfter).to.equal(supplyBefore);
    });
  });
  

  describe("TokenExchange (exchange.sol)", function () {
    let Token, token, Exchange, exchange;
    let owner, alice, bob;
    const u = (n, dec = 18) => ethers.utils.parseUnits(n.toString(), dec);
    const BASE = u(5000, 0);
  
    beforeEach(async function () {
      [owner, alice, bob] = await ethers.getSigners();
  
      // Deploy and seed Token
      Token = await ethers.getContractFactory("Token", owner);
      token = await Token.deploy();
      await token.deployed();
      // mint enough for pool + extra, then disable
      await token.mint(BASE.add(u(1000, 0)));
      await token.disable_mint();
  
      // Deploy Exchange pointing at that Token
      Exchange = await ethers.getContractFactory("TokenExchange", owner);
      exchange = await Exchange.deploy(token.address);
      await exchange.deployed();
  
      // Owner seeds initial pool with 5 000 wei + 5 000 tokens
      await token.connect(owner).approve(exchange.address, BASE);
      await exchange.connect(owner).createPool(BASE, { value: BASE });
    });
  
    describe("createPool", function () {
      it("initialises token & ETH reserves and onlyOwner", async function () {
        // check reserves
        expect(await token.balanceOf(exchange.address)).to.equal(BASE);
        expect(await ethers.provider.getBalance(exchange.address)).to.equal(BASE);
  
        // non-owner cannot call createPool again
        await expect(
          token.connect(alice).approve(exchange.address, BASE)
        ).to.be.ok; // alice can approve
        await expect(
          exchange.connect(alice).createPool(BASE, { value: BASE })
        ).to.be.revertedWith("Ownable: caller is not the owner");
      });
    });
  
    describe("getSwapFee", function () {
      it("returns the correct numerator and denominator", async function () {
        const [num, den] = await exchange.getSwapFee();
        expect(num).to.equal(3);
        expect(den).to.equal(100);
      });
    });
  
    describe("addLiquidity", function () {
    //   it("adds liquidity in proportion and mints LP tokens", async function () {
    //     // current rate = (token_reserves * 1e18) / eth_reserves = 1e18
    //     const currentRate = ethers.constants.WeiPerEther;
    //     const maxRate = currentRate.add(1);
    //     const minRate = currentRate.sub(1);
  
    //     // alice approves exactly 100 tokens for 100 wei deposit
    //     await token.connect(alice).approve(exchange.address, u(100, 0));
  
    //     await exchange
    //       .connect(alice)
    //       .addLiquidity(maxRate, minRate, { value: u(100, 0) });
  
    //     // pool reserves bumped
    //     expect(await token.balanceOf(exchange.address)).to.equal(BASE.add(u(100, 0)));
    //     expect(await ethers.provider.getBalance(exchange.address)).to.equal(BASE.add(u(100, 0)));
  
    //     // lps mapping tracks ETH contributed
    //     expect(await exchange.lps(alice.address)).to.equal(u(100, 0));
  
    //     // totalLPSupply and lpBalances minted
    //     expect(await exchange.totalLPSupply()).to.equal(u(100, 0));
    //     expect(await exchange.lpBalances(alice.address)).to.equal(u(100, 0));
    //   });
  
      it("reverts if pool not initialised or no ETH sent", async function () {
        // deploy fresh uninitialised exchange
        const freshEx = await Exchange.deploy(token.address);
        await freshEx.deployed();
  
        // no pool => revert
        await expect(
          freshEx.connect(alice).addLiquidity(1, 0, { value: u(1, 0) })
        ).to.be.revertedWith("Pool is not initialised");
  
        // zero ETH => revert
        await expect(
          exchange.connect(alice).addLiquidity(ethers.constants.MaxUint256, 0, { value: 0 })
        ).to.be.revertedWith("NO ETH sent");
      });
  
      it("reverts on slippage out-of-bounds", async function () {
        // currentRate = 1e18
        const currentRate = ethers.constants.WeiPerEther;
  
        // alice approves tokens
        await token.connect(alice).approve(exchange.address, u(1, 0));
  
        // max < rate => revert
        await expect(
          exchange.connect(alice).addLiquidity(
            currentRate.sub(1),
            currentRate.sub(2),
            { value: u(1, 0) }
          )
        ).to.be.revertedWith("Slippage");
      });
    });
  
    // describe("removeLiquidity & removeAllLiquidity", function () {
    //   beforeEach(async function () {
    //     // alice adds 100 wei liquidity
    //     const rate = ethers.constants.WeiPerEther;
    //     await token.connect(alice).approve(exchange.address, u(100, 0));
    //     await exchange
    //       .connect(alice)
    //       .addLiquidity(rate.add(1), rate.sub(1), { value: u(100, 0) });
    //   });
  
    //   it("removes a portion of liquidity and returns correct amounts", async function () {
    //     const ethBefore = await ethers.provider.getBalance(alice.address);
    //     const tokBefore = await token.balanceOf(alice.address);
  
    //     // remove 50 wei
    //     await exchange.connect(alice).removeLiquidity(u(50, 0), ethers.constants.MaxUint256, 0);
  
    //     const ethAfter = await ethers.provider.getBalance(alice.address);
    //     const tokAfter = await token.balanceOf(alice.address);
  
    //     // she got ~50 wei back
    //     expect(ethAfter.sub(ethBefore)).to.equal(u(50, 0));
    //     // tokens returned in proportion (~50)
    //     expect(tokAfter.sub(tokBefore)).to.equal(u(50, 0));
  
    //     // lps mapping decreased
    //     expect(await exchange.lps(alice.address)).to.equal(u(50, 0));
    //   });
  
    //   it("removes all liquidity via removeAllLiquidity", async function () {
    //     const ethBefore = await ethers.provider.getBalance(alice.address);
  
    //     await exchange.connect(alice).removeAllLiquidity(ethers.constants.MaxUint256, 0);
  
    //     const ethAfter = await ethers.provider.getBalance(alice.address);
    //     expect(ethAfter.sub(ethBefore)).to.equal(u(100, 0));
  
    //     // no LP left
    //     expect(await exchange.lps(alice.address)).to.equal(0);
    //   });
  
    //   it("reverts if too much LP is withdrawn or drains pool", async function () {
    //     // too big withdrawal
    //     await expect(
    //       exchange.connect(alice).removeLiquidity(u(200, 0), ethers.constants.MaxUint256, 0)
    //     ).to.be.revertedWith("Not enough LP");
  
    //     // drain ETH entirely => revert
    //     await expect(
    //       exchange.connect(alice).removeLiquidity(BASE.add(u(100, 0)), ethers.constants.MaxUint256, 0)
    //     ).to.be.revertedWith("Drain ETH");
    //   });
    // });
  
    describe("swap functions", function () {
      it("swaps tokens for ETH with fee and updates reserves", async function () {
        // bob needs some tokens first
        await token.transfer(bob.address, u(100, 0));
        await token.connect(bob).approve(exchange.address, u(100, 0));
  
        const ethPool0 = await ethers.provider.getBalance(exchange.address);
        const tokPool0 = await token.balanceOf(exchange.address);
  
        // bob swaps 100 tokens
        await exchange.connect(bob).swapTokensForETH(u(100, 0), ethers.constants.MaxUint256);
  
        const ethPool1 = await ethers.provider.getBalance(exchange.address);
        const tokPool1 = await token.balanceOf(exchange.address);
  
        // pool ETH decreased
        expect(ethPool1).to.be.lt(ethPool0);
        // pool tokens increased by full 100
        expect(tokPool1.sub(tokPool0)).to.equal(u(100, 0));
      });
  
      it("swaps ETH for tokens with fee and updates reserves", async function () {
        const ethPool0 = await ethers.provider.getBalance(exchange.address);
        const tokPool0 = await token.balanceOf(exchange.address);
  
        // alice swaps 50 wei
        await exchange.connect(alice).swapETHForTokens(0, { value: u(50, 0) });
  
        const ethPool1 = await ethers.provider.getBalance(exchange.address);
        const tokPool1 = await token.balanceOf(exchange.address);
  
        // pool ETH increased
        expect(ethPool1).to.equal(ethPool0.add(u(50, 0)));
        // pool tokens decreased
        expect(tokPool1).to.be.lt(tokPool0);
      });
  
      it("reverts on zero-amount swaps", async function () {
        await expect(
          exchange.connect(bob).swapTokensForETH(0, ethers.constants.MaxUint256)
        ).to.be.revertedWith("Zero amount");
        await expect(
          exchange.connect(alice).swapETHForTokens(0, { value: 0 })
        ).to.be.revertedWith("Zero amount");
      });
  
      it("reverts on slippage out-of-bounds for swaps", async function () {
        // token→ETH: supply tight maxRate = currentRate - 1
        const curr = await ethers.provider
          .getBalance(exchange.address)
          .then((eth0) =>
            token
              .balanceOf(exchange.address)
              .then((tok0) => tok0.mul(ethers.constants.WeiPerEther).div(eth0))
          );
        // bob gets tokens
        await token.transfer(bob.address, u(10, 0));
        await token.connect(bob).approve(exchange.address, u(10, 0));
        await expect(
          exchange.connect(bob).swapTokensForETH(u(10, 0), curr.sub(1))
        ).to.be.revertedWith("Slippage");
  
        // ETH→token: minRate = currentRate + 1
        const curr2 = curr;
        await expect(
          exchange.connect(alice).swapETHForTokens(curr2.add(1), { value: u(1, 0) })
        ).to.be.revertedWith("Slippage (min rate)");
      });
    });
  });
  
  
  
  
  
  
  
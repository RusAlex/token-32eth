const Token = artifacts.require("Token");

contract("Sending Ether to Token", accounts => {
  it("sender balance equals 1 Token, makes contract balance 1 eth", () =>
    Token.deployed().then(instance =>
      web3.eth
        .sendTransaction({
          from: accounts[0],
          to: instance.address,
          value: web3.utils.toWei("1", "ether"),
          gas: 500000
        })
        .then(() => instance.balanceOf(accounts[0]))
        .then(bal => assert.equal(bal, web3.utils.toWei("1", "ether")))
        .then(() => web3.eth.getBalance(instance.address))
        .then(bal => assert.equal(bal, web3.utils.toWei("1", "ether")))
    ));

  it("Withdrawal works", () =>
    Token.deployed().then(instance => {
      let accountBalance;
      return web3.eth
        .getBalance(instance.address)
        .then(bal => assert.equal(bal, web3.utils.toWei("1", "ether")))
        .then(() => web3.eth.getBalance(accounts[0]))
        .then(bal => (accountBalance = bal))
        .then(() => instance.withdrawEther())
        .then(() => web3.eth.getBalance(instance.address))
        .then(bal => assert.equal(bal, web3.utils.toWei("0", "ether")))
        .then(() => web3.eth.getBalance(accounts[0]))
        .then(bal =>
          assert.isTrue(
            Number(web3.utils.fromWei((bal - accountBalance).toFixed())) > 0.9,
            "account balance increased more than 0.9 ETH"
          )
        );
    }));

  it("Dividends works", () => {
    return Token.deployed().then(instance =>
      web3.eth
        .sendTransaction({
          from: accounts[1],
          to: instance.address,
          value: web3.utils.toWei("1", "ether"),
          gas: 500000
        })
        .then(() => instance.balanceOf(accounts[1]))
        .then(bal => assert.equal(bal, web3.utils.toWei("1", "ether")))
        .then(() =>
          instance.transfer(accounts[2], web3.utils.toWei("1", "ether"), {
            from: accounts[1]
          })
        )
        .then(() => instance.balanceOf(accounts[1]))
        .then(bal => assert.equal(web3.utils.fromWei(bal), 0))
        .then(() => instance.balanceOf(accounts[2]))
        .then(bal => assert.equal(bal, web3.utils.toWei("1", "ether")))
        .then(() => instance.dividendTracker())
        .then(address =>
          web3.eth.sendTransaction({
            from: accounts[0],
            to: address,
            value: web3.utils.toWei("2", "ether")
          })
        )
        .then(() => instance.withdrawableDividendOf(accounts[2]))
        .then(bal => {
          assert.equal(web3.utils.fromWei(bal), 1);
        })
    );
  });
});

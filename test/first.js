const Token = artifacts.require("Token");

contract("test", accounts => {
  it("should work", () =>
    Token.deployed().then(instance =>
      instance
        .send(web3.utils.toWei("1", "ether"), accounts[0])
        .then(() => instance.balanceOf(accounts[0]))
        .then(bal => assert.equal(bal, web3.utils.toWei("1", "ether")))
        .then(() => web3.eth.getBalance(instance.address))
        .then(bal => assert.equal(bal, web3.utils.toWei("1", "ether")))
    ));
});

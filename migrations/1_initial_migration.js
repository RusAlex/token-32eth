const Migrations = artifacts.require("Migrations");
const Token = artifacts.require("Token");
const IterableMapping = artifacts.require("IterableMapping");

module.exports = function (deployer) {
  deployer.deploy(Migrations);
  deployer.deploy(IterableMapping);
  deployer.link(IterableMapping, Token);
  deployer.deploy(Token);
};

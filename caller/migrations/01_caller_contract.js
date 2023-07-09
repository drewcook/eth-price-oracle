const Caller = artifacts.require('Caller')

module.exports = function (deployer) {
  deployer.deploy(Caller)
}
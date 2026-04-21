const CampusAssetBooking = artifacts.require("CampusAssetBooking");

module.exports = function(deployer) {
  deployer.deploy(CampusAssetBooking);
};

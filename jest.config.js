const { jestConfig } = require("@salesforce/sfdx-lwc-jest/config");

// One fixed browser time zone for every test, far from the demo branches, so time zone bugs show up on any machine.
process.env.TZ = "America/Los_Angeles";

module.exports = {
  ...jestConfig,
  modulePathIgnorePatterns: ["<rootDir>/.localdevserver", "<rootDir>/.claude"]
};

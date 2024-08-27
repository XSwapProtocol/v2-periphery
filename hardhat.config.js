require("dotenv").config();

let mnemonic = process.env.MNEMONIC;

module.exports = {
    paths: {
        artifacts: "./artifacts"
    },
    solidity: {
        version: "0.6.6",
        settings: {
            optimizer: {
                enabled: true,
                runs: 200,
            },
        },
    },
    networks: {
        xdc: {
            url: "https://erpc.xinfin.network",
            chainId: 50,
            accounts: {
                mnemonic: mnemonic,
                initialIndex: 1
            },
        },
    },
};

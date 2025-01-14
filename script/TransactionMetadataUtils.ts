import * as bitcoin from "bitcoinjs-lib";
import axios from "axios";

export function createBinaryMetadataBuffer(params: {
  receiverAddress: string;
  lockedAmount: number;
  chainId: number;
  baseTokenAmount: number;
}): Buffer {
  // const addressBytes = parseEthAddressToBytes(params.receiverAddress);
  const addressBytes = Buffer.from(params.receiverAddress, "hex");
  const lockedAmountBuf = encodeU64(params.lockedAmount);

  const chainIdBuf = encodeU32(params.chainId);
  const baseTokenBuf = encodeU64(params.baseTokenAmount);

  // Wrap each field with 2-byte length prefix
  const encodedFields = [
    encodeWithTwoByteLength(addressBytes),
    encodeWithTwoByteLength(lockedAmountBuf),
    encodeWithTwoByteLength(chainIdBuf),
    encodeWithTwoByteLength(baseTokenBuf),
  ];
  console.log("Encoded Fields lenght:", Buffer.concat(encodedFields).length);
  return Buffer.concat(encodedFields);
}

/**
 * Encode a 32-bit unsigned integer in big-endian (4 bytes).
 * I chainId can be larger than 2^32 - 1, we need 8 bytes or variable encoding.
 */
export function encodeU32(value: number): Buffer {
  const buf = Buffer.alloc(4);
  buf.writeUInt32BE(value, 0);
  return buf;
}

/**
 * Encode a 64-bit unsigned integer in big-endian (8 bytes).
 * For amounts that can exceed 2^32, we use 64-bit.
 */
export function encodeU64(value: number): Buffer {
  const buf = Buffer.alloc(8);
  buf.writeBigUInt64BE(BigInt(value), 0);
  return buf;
}

/**
 * Wrap a Buffer with a 2-byte length prefix (big-endian).
 */
export function encodeWithTwoByteLength(data: Buffer): Buffer {
  const prefix = Buffer.alloc(2);
  prefix.writeUInt16BE(data.length, 0);
  return Buffer.concat([prefix, data]);
}

export async function decodeTransactionMetadata(
  txid: string,
  apiConfig: { primary: string; fallback: string }
) {
  const { data: rawTxHex } = await axios.get(
    `${apiConfig.primary}/tx/${txid}/hex`
  );
  // Getting the return value from above as (based on the provided transaction id)
  // let directRawTxHex =
  //   "02000000000103b82cad481c890decb880b2d42acf5360ea8e7b9ddfee889230b93aa6b648bb220300000000ffffffffa97e322ae9cfca10dc96d37e7092b7de7cdf6b88c553f2b2aef9a41e6385e9400300000000ffffffff628916f367a67c274ae9b000707d1460568ed6195174f3a3c6a2698e9a8336600200000000ffffffff04e80300000000000016001471d044aeb7f41205a9ef0e3d785e7d38a776cfa1d00700000000000016001471d044aeb7f41205a9ef0e3d785e7d38a776cfa10000000000000000326a30001403aa93e006fba956cdbafa2b8ef789d0cb63e7b40008000000000000271000040000000000080000000000004e205a02000000000000160014d6a279dc882b830c5562b49e3e25bf3c5767ab730247304402207134570d7db730194c14cc7a08cd1320e96335ff228ee5d74487b5a50777a8d902207f75fcd95b0e54336bae8445a64a6064c4d633281d0d1780a8016a24720696b901210226795246077d56dfbc6730ef3a6833206a34f0ba1bd6a570de14d49c42781ddb02483045022100f050f18a67830c00e58842efbfd58b8d50d23b914fa452188c4b9126b1a19ee102205f26aec29c67344de9ab6692899e95801e7d21031f35208598f12b806d355d2c01210226795246077d56dfbc6730ef3a6833206a34f0ba1bd6a570de14d49c42781ddb0247304402204e31b84211cc2cee86bf431d1c9f6985f6e4532395106ac4fca6d6123811bdd502204a2a59ea6e76c2bb6f13ce714e4a8745ad1bb7b1770dae768a5c61f5cd0ed55f01210226795246077d56dfbc6730ef3a6833206a34f0ba1bd6a570de14d49c42781ddb00000000";
  console.log("Raw Transaction Hex:", rawTxHex);
  const tx = bitcoin.Transaction.fromHex(rawTxHex);
  console.log("Transaction:", tx);

  const opReturnOutput = tx.outs.find((out) =>
    out.script.toString("hex").startsWith("6a")
  );
  console.log("OpReturnOutput:", opReturnOutput);

  if (opReturnOutput) {
    const data = bitcoin.script.decompile(opReturnOutput.script);
    console.log("data:", data);
    console.log("data[1]:", data);
    if (data && data[1]) {
      return decodeBinaryMetadataBuffer(data[1] as Buffer); // This gives the desired outpue
    }
  }

  throw new Error("No metadata found in transaction.");
}

//Decode binary metadata Buffer

function decodeBinaryMetadataBuffer(buffer: Buffer) {
  let offset = 0;

  function readLengthPrefixed(): Buffer {
    const length = buffer.readUInt16BE(offset);
    offset += 2;
    const field = buffer.slice(offset, offset + length);
    offset += length;
    return field;
  }
  const receiverAddressHex = readLengthPrefixed().toString("hex");
  const receiverAddress = receiverAddressHex;

  const lockedAmountHex = readLengthPrefixed().toString("hex");
  const lockedAmount = BigInt("0x" + lockedAmountHex);

  const chainIdHex = readLengthPrefixed().toString("hex");
  const chainId = parseInt(chainIdHex, 16);

  const baseTokenHex = readLengthPrefixed().toString("hex");
  const baseTokenAmount = BigInt("0x" + baseTokenHex);

  return {
    receiverAddress,
    lockedAmount,
    chainId,
    baseTokenAmount,
  };
}

// const txid = "503073f7f882e72b289ead47fef2babf0a1830912ae2344b2b529b37bd14e9e7"; // old txid with chainId 0 and baseTokenAmount 0
const txid = "2d867dd7068954afea9918343a2df8ae29780fbf863788df567a480e5e6754f2"; // new txid
decodeTransactionMetadata(txid, {
  primary: "https://blockstream.info/testnet/api",
  fallback: "https://blockstream.info/testnet/api",
})
  .then((metadata) => {
    console.log("decoded metadata: ", metadata);
  })
  .catch((error) => {
    console.log(error);
  });

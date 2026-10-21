import { webcrypto } from "node:crypto";

const pair = await webcrypto.subtle.generateKey("Ed25519", true, ["sign", "verify"]);
const privateKey = Buffer.from(await webcrypto.subtle.exportKey("pkcs8", pair.privateKey)).toString("base64");
const publicKey = Buffer.from(await webcrypto.subtle.exportKey("raw", pair.publicKey)).toString("base64");
console.log(JSON.stringify({ privateKey, publicKey }, null, 2));

import crypto from 'crypto';

const ALGORITHM = "aes-256-gcm";
const ENCRYPTION_KEY = Buffer.from("YOUR_WALLET_ENCRYPTION_KEY_HERE", "hex");

function encrypt(text) {
  const iv = crypto.randomBytes(16);
  const cipher = crypto.createCipheriv(ALGORITHM, ENCRYPTION_KEY, iv);
  let enc = cipher.update(text, "utf8", "hex");
  enc += cipher.final("hex");
  return `${iv.toString("hex")}:${cipher.getAuthTag().toString("hex")}:${enc}`;
}

function decrypt(encText) {
  const [ivHex, tagHex, enc] = encText.split(":");
  const decipher = crypto.createDecipheriv(ALGORITHM, ENCRYPTION_KEY, Buffer.from(ivHex, "hex"));
  decipher.setAuthTag(Buffer.from(tagHex, "hex"));
  let dec = decipher.update(enc, "hex", "utf8");
  dec += decipher.final("utf8");
  return dec;
}

try {
  const decrypted = decrypt("YOUR_MASTER_WALLET_SECRET_KEY_HERE");
  console.log("✅ Already encrypted. Decrypted:", decrypted);
} catch(e) {
  console.log("❌ Not encrypted. Encrypting now...");
  const encrypted = encrypt("YOUR_MASTER_WALLET_SECRET_KEY_HERE");
  console.log("✅ Use this in Railway:", encrypted);
}

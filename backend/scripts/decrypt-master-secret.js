#!/usr/bin/env node
import crypto from 'crypto';
import dotenv from 'dotenv';

dotenv.config();

const ALGORITHM = 'aes-256-gcm';
const ENCRYPTION_KEY = Buffer.from(
  process.env.WALLET_ENCRYPTION_KEY || 'a'.repeat(64),
  'hex',
);

function decrypt(encText) {
  try {
    const [ivHex, tagHex, enc] = encText.split(':');
    const decipher = crypto.createDecipheriv(ALGORITHM, ENCRYPTION_KEY, Buffer.from(ivHex, 'hex'));
    decipher.setAuthTag(Buffer.from(tagHex, 'hex'));
    let dec = decipher.update(enc, 'hex', 'utf8');
    dec += decipher.final('utf8');
    return dec;
  } catch (err) {
    return null;
  }
}

const encrypted = process.env.MASTER_WALLET_SECRET_KEY;
console.log('🔓 Attempting to decrypt master wallet secret...\n');
console.log(`Encrypted: ${encrypted}\n`);

const decrypted = decrypt(encrypted);

if (decrypted) {
  console.log('✅ Successfully decrypted!');
  console.log(`🔑 Original Secret Key: ${decrypted}\n`);
  console.log('This is your unencrypted Stellar secret (starts with S). Keep it safe!');
} else {
  console.log('❌ Decryption failed!');
  console.log('The WALLET_ENCRYPTION_KEY does not match the key used to encrypt the secret.');
  console.log('\nThis means the secret was encrypted with a DIFFERENT key.');
  console.log('Solution: Create a new master wallet and fund it from the old one.');
}
